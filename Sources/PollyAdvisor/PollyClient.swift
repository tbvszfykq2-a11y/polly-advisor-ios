import Foundation
import Security

// MARK: - Errors

enum PollyError: LocalizedError {
    case badURL
    case unauthorized
    case server(Int)
    case transport(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Server address is not a valid URL. Example: http://10.200.200.1:8793"
        case .unauthorized:
            return "Authentication failed — the username or password was rejected."
        case .server(let code):
            return "Server returned HTTP \(code)."
        case .transport(let message):
            return "Cannot reach the advisor: \(message)"
        case .decode(let message):
            return "Unexpected response from the advisor: \(message)"
        }
    }

    /// Short form for the status bar.
    var short: String {
        switch self {
        case .badURL:        return "BAD URL"
        case .unauthorized:  return "AUTH"
        case .server(let c): return "HTTP \(c)"
        case .transport:     return "NO LINK"
        case .decode:        return "BAD DATA"
        }
    }
}

// MARK: - Keychain

/// The API password never goes to UserDefaults. Keychain only.
enum Keychain {
    private static let service = "com.hermes.pollyadvisor"

    static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        if value.isEmpty { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Client

/// Thin, stateless HTTP client for the advisor API.
struct PollyClient {
    var baseURL: URL
    var user: String
    var pass: String

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private var authHeader: String {
        "Basic " + Data("\(user):\(pass)".utf8).base64EncodedString()
    }

    private func makeURL(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PollyError.badURL
        }
        var basePath = comps.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        comps.path = basePath + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw PollyError.badURL }
        return url
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], type: T.Type) async throws -> T {
        var req = URLRequest(url: try makeURL(path, query: query))
        req.httpMethod = "GET"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: req)
        } catch {
            throw PollyError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PollyError.transport("no HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PollyError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PollyError.server(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PollyError.decode(error.localizedDescription)
        }
    }

    // MARK: Endpoints

    func state() async throws -> StateResponse {
        try await get("api/state", type: StateResponse.self)
    }

    func advice(limit: Int = 60) async throws -> [Advice] {
        // The endpoint may return a bare array or an object with an `advice` key
        // depending on version; decode leniently.
        struct Wrapper: Decodable { let advice: [Advice]? }
        var req = URLRequest(url: try makeURL("api/advice", query: [URLQueryItem(name: "limit", value: "\(limit)")]))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: req)
        } catch {
            throw PollyError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PollyError.transport("no HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw PollyError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw PollyError.server(http.statusCode) }

        let decoder = JSONDecoder()
        if let list = try? decoder.decode([Advice].self, from: data) { return list }
        if let wrapped = try? decoder.decode(Wrapper.self, from: data) { return wrapped.advice ?? [] }
        return []
    }

    func scorecard(days: Int = 7) async throws -> Scorecard {
        try await get("api/scorecard",
                      query: [URLQueryItem(name: "days", value: "\(days)")],
                      type: Scorecard.self)
    }

    func execStatus() async throws -> ExecStatus {
        try await get("api/exec", type: ExecStatus.self)
    }

    /// Lightweight reachability probe used by Settings.
    func ping() async throws {
        _ = try await get("healthz", type: PingBody.self)
    }

    private struct PingBody: Decodable { let ok: Bool? }
}
