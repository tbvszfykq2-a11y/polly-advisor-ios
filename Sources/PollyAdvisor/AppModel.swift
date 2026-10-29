import SwiftUI
import Combine

/// Single source of truth for the UI. Owns settings, the polling loop, and a
/// short in-memory history so each window can draw a live sparkline without a
/// server-side time-series endpoint.
@MainActor
final class AppModel: ObservableObject {

    // MARK: Settings
    @Published var serverURL: String
    @Published var username: String
    @Published var password: String
    @Published var pollSeconds: Double

    // MARK: Live data
    @Published private(set) var state: StateResponse?
    @Published private(set) var advice: [Advice] = []
    @Published private(set) var scorecard: Scorecard?
    @Published private(set) var exec: ExecStatus?
    @Published private(set) var conn: ConnState = .idle
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var history: [String: [Point]] = [:]

    struct Point: Identifiable {
        let id = UUID()
        let t: Double
        let spot: Double
        let pUp: Double
    }

    private var loopTask: Task<Void, Never>?
    private var tick = 0

    // MARK: Init

    init() {
        let d = UserDefaults.standard
        serverURL = d.string(forKey: "polly.server") ?? "http://10.200.200.1:8793"
        username  = d.string(forKey: "polly.user") ?? "advisor"
        password  = Keychain.get("password") ?? ""
        let stored = d.double(forKey: "polly.poll")
        pollSeconds = stored >= 1 ? stored : 2
    }

    // MARK: Derived

    var isConfigured: Bool {
        !password.isEmpty && URL(string: serverURL)?.scheme != nil
    }

    var needsSetup: Bool { !isConfigured }

    var windows: [MarketWindow] { state?.windows ?? [] }

    /// Windows where a side currently clears the fee hurdle, best edge first.
    var actionable: [MarketWindow] {
        windows
            .filter { ($0.snapshot?.bestEdge ?? 0) > 0 }
            .sorted { ($0.snapshot?.bestEdge ?? 0) > ($1.snapshot?.bestEdge ?? 0) }
    }

    /// Everything with time left, soonest close first.
    var tracked: [MarketWindow] {
        windows.sorted { ($0.tRemaining ?? .greatestFiniteMagnitude) <
                        ($1.tRemaining ?? .greatestFiniteMagnitude) }
    }

    var quotingCount: Int {
        windows.filter { $0.snapshot?.upAsk != nil && $0.snapshot?.downAsk != nil }.count
    }

    var newestAdvice: Advice? { advice.first }

    func points(for window: MarketWindow) -> [Point] {
        history[window.id] ?? []
    }

    // MARK: Settings persistence

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(serverURL, forKey: "polly.server")
        d.set(username, forKey: "polly.user")
        d.set(pollSeconds, forKey: "polly.poll")
        Keychain.set(password, account: "password")
    }

    var client: PollyClient? {
        guard let url = URL(string: serverURL),
              let scheme = url.scheme, ["http", "https"].contains(scheme)
        else { return nil }
        return PollyClient(baseURL: url, user: username, pass: password)
    }

    // MARK: Polling

    func start() {
        guard loopTask == nil, isConfigured else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = max(0.75, self.pollSeconds)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Restart after settings change so a new host/credential takes effect now.
    func reconnect() {
        stop()
        state = nil
        history = [:]
        advice = []
        scorecard = nil
        exec = nil
        conn = .idle
        lastError = nil
        tick = 0
        start()
    }

    func refresh() async {
        guard let client else {
            conn = .failed("BAD URL")
            lastError = PollyError.badURL.errorDescription
            return
        }
        if state == nil { conn = .connecting }

        do {
            let fresh = try await client.state()
            state = fresh
            conn = .live
            lastError = nil
            lastUpdate = Date()
            ingest(fresh)
            tick += 1

            if tick % 3 == 0 || advice.isEmpty {
                if let list = try? await client.advice(limit: 80) { advice = list }
            }
            if scorecard == nil || tick % 30 == 0 {
                scorecard = try? await client.scorecard(days: 7)
                exec = try? await client.execStatus()
            }
        } catch let error as PollyError {
            conn = state == nil ? .failed(error.short) : .stale
            lastError = error.errorDescription
        } catch {
            conn = state == nil ? .failed("ERROR") : .stale
            lastError = error.localizedDescription
        }
    }

    /// Probe used by the settings sheet before committing a new host.
    func testConnection() async -> Result<Double, Error> {
        guard let client else { return .failure(PollyError.badURL) }
        let started = Date()
        do {
            _ = try await client.state()
            return .success(Date().timeIntervalSince(started))
        } catch {
            return .failure(error)
        }
    }

    private func ingest(_ s: StateResponse) {
        guard let incoming = s.windows else { return }
        var next = history
        let liveIDs = Set(incoming.map(\.id))

        for w in incoming {
            guard let snap = w.snapshot,
                  let spot = snap.spot,
                  let pUp = snap.pUp
            else { continue }
            var series = next[w.id] ?? []
            series.append(Point(t: snap.ts ?? s.now ?? 0, spot: spot, pUp: pUp))
            if series.count > 150 { series.removeFirst(series.count - 150) }
            next[w.id] = series
        }

        // Drop buffers for windows that have rolled off the board.
        next = next.filter { liveIDs.contains($0.key) }
        history = next
    }
}
