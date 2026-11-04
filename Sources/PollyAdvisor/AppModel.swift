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
    /// The server's retrospective over settled markets. Refreshed on its own
    /// slow cadence: the payload is cached server-side for 60 s and the queries
    /// behind it scan the advice table, so polling it with the live board would
    /// be wasted work on both ends.
    @Published private(set) var review: ReviewResponse?
    @Published private(set) var conn: ConnState = .idle
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var history: [String: [Point]] = [:]

    struct Point: Identifiable {
        /// Identity is the sample time, not a fresh UUID. A UUID per point meant
        /// every poll replaced the identity of all 1,200 buffered samples, so the
        /// sparklines could never reuse a row diff and redrew from scratch each
        /// second.
        var id: Double { t }
        let t: Double
        let spot: Double
        let pUp: Double
    }

    private var loopTask: Task<Void, Never>?
    /// The auxiliary fetch, tracked so it can be cancelled with the loop. Before
    /// this it survived `stop()`, and a response arriving after a reconnect
    /// could write one server's review or scorecard into a session pointed at
    /// another.
    private var auxTask: Task<Void, Never>?
    private var tick = 0
    /// Auxiliary fetches run on their own timestamps so changing the poll
    /// interval cannot silently change how often the scorecard or review is
    /// refetched.
    private var lastAdviceFetch = Date.distantPast
    private var lastStatsFetch = Date.distantPast
    private var lastReviewFetch = Date.distantPast
    private var auxInFlight = false

    /// Floor for the poll interval. The server evaluates every 250 ms, so a
    /// sub-second board is accurate; anything slower than a couple of seconds
    /// starts showing prices the book has already moved past.
    static let minPollSeconds: Double = 0.5
    static let defaultPollSeconds: Double = 1.0

    // MARK: Init

    init() {
        let d = UserDefaults.standard
        serverURL = d.string(forKey: "polly.server") ?? "http://10.200.200.1:8793"
        username  = d.string(forKey: "polly.user") ?? "advisor"
        password  = Keychain.get("password") ?? ""
        let stored = d.double(forKey: "polly.poll")
        // Older builds stored a 2 s default; keep a user's choice but never sit
        // slower than the default just because the key was absent.
        pollSeconds = stored >= Self.minPollSeconds ? stored : Self.defaultPollSeconds
    }

    // MARK: Derived

    var isConfigured: Bool {
        !password.isEmpty && URL(string: serverURL)?.scheme != nil
    }

    var needsSetup: Bool { !isConfigured }

    var windows: [MarketWindow] { state?.windows ?? [] }

    /// Markets open right now. This is the only list the board renders, and the
    /// only list a trade can come from — a window that has closed cannot be
    /// entered, and a window that has not opened cannot be entered either.
    var activeWindows: [MarketWindow] {
        windows
            .filter { $0.isActivelyOpen }
            .sorted { ($0.tRemaining ?? .greatestFiniteMagnitude) <
                      ($1.tRemaining ?? .greatestFiniteMagnitude) }
    }

    /// The next window per contract length, soonest to open first. These carry a
    /// prediction, not an entry: the engine prices them from momentum and the
    /// book before the opening TWAP exists.
    var nextWindows: [MarketWindow] {
        windows
            .filter { $0.isPreopen }
            .sorted { ($0.secondsToOpen ?? .greatestFiniteMagnitude) <
                      ($1.secondsToOpen ?? .greatestFiniteMagnitude) }
    }

    /// Windows the engine is willing to trade, strongest first.
    ///
    /// The raw edge maths alone is not the gate: `edgeUp` stays positive on
    /// windows the engine answered WATCH, so filtering on it resurrected trades
    /// the server had explicitly declined. A window qualifies only through
    /// `isTradeable`, which prefers a server-validated verdict and falls back to
    /// a band-guarded edge when the engine said nothing at all.
    var actionable: [MarketWindow] {
        activeWindows
            .filter { $0.snapshot?.isTradeable == true }
            .sorted { rank($0) > rank($1) }
    }

    /// Strength used to order tradeable windows: a server-validated verdict
    /// outranks a bare-edge fallback, then the larger edge wins.
    private func rank(_ w: MarketWindow) -> Double {
        guard let s = w.snapshot else { return -1 }
        let base = s.advice?.edge ?? s.bestEdge ?? 0
        return s.serverValidatedTrade ? base + 1 : base
    }

    /// Everything with time left, soonest close first.
    var tracked: [MarketWindow] {
        windows.sorted { ($0.tRemaining ?? .greatestFiniteMagnitude) <
                        ($1.tRemaining ?? .greatestFiniteMagnitude) }
    }

    var quotingCount: Int {
        windows.filter { $0.snapshot?.upAsk != nil && $0.snapshot?.downAsk != nil }.count
    }

    /// The strongest market on the board, quoted ones only.
    ///
    /// Deliberately does not require a positive edge: the card is pinned always,
    /// and "no edge, stand down" is information. Ties break toward the window
    /// closing sooner, since that edge decays first.
    ///
    /// Restricted to windows that are open. A pre-open window has a prediction
    /// but no entry — pinning it as "the best trade" would advertise a market the
    /// reader cannot act on yet, which is the same mistake as showing closed ones.
    var bestTrade: MarketWindow? {
        let live = activeWindows.filter {
            $0.snapshot?.upAsk != nil || $0.snapshot?.downAsk != nil
        }
        guard !live.isEmpty else { return nil }
        // Rank on the gate, not the raw edge: a server-validated trade beats a
        // fallback, and a window the engine declined must not outrank one it
        // endorsed just because its arithmetic edge happens to be larger.
        return live.max { a, b in
            let sa = a.snapshot, sb = b.snapshot
            let ta = sa?.serverValidatedTrade == true ? 2 : (sa?.isTradeable == true ? 1 : 0)
            let tb = sb?.serverValidatedTrade == true ? 2 : (sb?.isTradeable == true ? 1 : 0)
            if ta != tb { return ta < tb }
            let ea = rank(a), eb = rank(b)
            if abs(ea - eb) > 0.0005 { return ea < eb }
            return (a.tRemaining ?? .greatestFiniteMagnitude) >
                   (b.tRemaining ?? .greatestFiniteMagnitude)
        }
    }

    /// Open markets for one contract length, soonest to close first.
    func markets(minutes: Int) -> [MarketWindow] {
        activeWindows.filter { $0.intervalMinutes == minutes }
    }

    /// Contract lengths the board reports, in display order.
    var intervalMinutes: [Int] { [5, 10, 15] }

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

    /// Start polling. Always refreshes immediately, so returning to the app
    /// draws live prices on the first frame instead of the values from whenever
    /// iOS suspended the process.
    func start() {
        guard isConfigured else { return }
        // Restart unconditionally. The old `guard loopTask == nil` meant that a
        // task which had ended for any reason left `loopTask` non-nil forever,
        // and every later `start()` was a no-op — the board simply stopped
        // updating until the app was force-quit.
        loopTask?.cancel()
        auxTask?.cancel()
        auxTask = nil
        // A task cancelled mid-flight would otherwise leave this latch set and
        // silently stop every later auxiliary fetch.
        auxInFlight = false
        loopTask = Task { [weak self] in
            var deadline = Date()
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                guard !Task.isCancelled else { return }
                // Advance the deadline instead of sleeping a fresh interval.
                // Sleeping `interval` *after* each request folds the request's
                // own latency into the period, so a 1 s setting quietly ran at
                // ~1.3 s and the board lagged the book further than it had to.
                let interval = max(Self.minPollSeconds, min(self.pollSeconds, 10))
                deadline = deadline.addingTimeInterval(interval)
                let wait = deadline.timeIntervalSinceNow
                if wait <= 0 {
                    // A slow request overran the period. Resync rather than
                    // running a backlog of back-to-back fetches.
                    deadline = Date()
                    continue
                }
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        auxTask?.cancel()
        auxTask = nil
        auxInFlight = false
    }

    /// Restart after settings change so a new host/credential takes effect now.
    func reconnect() {
        stop()
        state = nil
        history = [:]
        advice = []
        scorecard = nil
        exec = nil
        review = nil
        conn = .idle
        lastError = nil
        tick = 0
        lastAdviceFetch = .distantPast
        lastStatsFetch = .distantPast
        lastReviewFetch = .distantPast
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
            // The slow panels load in the background. Waiting for them here put
            // the 37 KB advice list and the scorecard scan in the same round
            // trip as the price, so every third tick was visibly late.
            refreshAuxiliary(client)
        } catch let error as PollyError {
            conn = state == nil ? .failed(error.short) : .stale
            lastError = error.errorDescription
        } catch {
            conn = state == nil ? .failed("ERROR") : .stale
            lastError = error.localizedDescription
        }
    }

    /// Queue the slow panels when their own cadence is due.
    ///
    /// Deliberately fire-and-forget: the live board must never wait on a table
    /// scan. `auxInFlight` stops a slow endpoint from stacking a queue of
    /// duplicate requests when the poll interval is short.
    private func refreshAuxiliary(_ client: PollyClient) {
        guard !auxInFlight else { return }
        let now = Date()
        let wantAdvice = advice.isEmpty || now.timeIntervalSince(lastAdviceFetch) >= 10
        let wantStats = scorecard == nil || now.timeIntervalSince(lastStatsFetch) >= 30
        let wantReview = review == nil || now.timeIntervalSince(lastReviewFetch) >= 60
        guard wantAdvice || wantStats || wantReview else { return }
        auxInFlight = true
        auxTask = Task { [weak self] in
            guard let self else { return }
            await self.loadAuxiliary(client: client, wantAdvice: wantAdvice,
                                     wantStats: wantStats, wantReview: wantReview)
        }
    }

    private func loadAuxiliary(client: PollyClient, wantAdvice: Bool,
                               wantStats: Bool, wantReview: Bool) async {
        if wantAdvice, let list = try? await client.advice(limit: 80) {
            advice = list
            lastAdviceFetch = Date()
        }
        if wantStats {
            if let sc = try? await client.scorecard(days: 7) {
                scorecard = sc
                lastStatsFetch = Date()
            }
            exec = try? await client.execStatus()
        }
        if wantReview, let rv = try? await client.review(limit: 12) {
            review = rv
            lastReviewFetch = Date()
        }
        // Cleared even if the task was cancelled, or the latch would stay set
        // and no auxiliary fetch would ever run again. The handle is not nil'd
        // here: a newer task may have replaced it while this one finished.
        auxInFlight = false
    }

    /// Pull-to-refresh on the review tab.
    ///
    /// The server caches this payload for 60 s, so a pull can legitimately
    /// return the same `generated_ts`. The view prints that timestamp rather
    /// than pretending the tap produced a fresh measurement.
    func refreshReview() async {
        guard let client else { return }
        if let rv = try? await client.review(limit: 12) {
            review = rv
            lastReviewFetch = Date()
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
            let t = snap.ts ?? s.now ?? 0
            // The server evaluates every 250 ms but the app polls on its own
            // interval; a repeated tick must not append a duplicate point or the
            // sparkline spends its 150-point budget on standing still.
            if let last = series.last, abs(last.t - t) < 0.001 { continue }
            series.append(Point(t: t, spot: spot, pUp: pUp))
            if series.count > 150 { series.removeFirst(series.count - 150) }
            next[w.id] = series
        }

        // Drop buffers for windows that have rolled off the board.
        next = next.filter { liveIDs.contains($0.key) }
        history = next
    }
}
