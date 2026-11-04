import Foundation
import SwiftUI

// MARK: - /api/state

struct StateResponse: Codable {
    let now: Double?
    let mode: String?
    let assets: [String]?
    let uptimeS: Double?
    let ticks: Int?
    let spot: [String: SpotHealth]?
    let twap: [String: TwapHealth]?
    let book: BookHealth?
    let windows: [MarketWindow]?
    let errors: [String: String]?
    let store: StoreStats?

    enum CodingKeys: String, CodingKey {
        case now, mode, assets, ticks, spot, twap, book, windows, errors, store
        case uptimeS = "uptime_s"
    }
}

struct SpotHealth: Codable {
    let venues: Int?
    let ageS: Double?
    let ring: Int?
    let chainlink: Bool?

    enum CodingKeys: String, CodingKey {
        case venues, ring, chainlink
        case ageS = "age_s"
    }
}

struct TwapHealth: Codable {
    let ageS: Double?
    let points: Int?
    let fresh: Bool?

    enum CodingKeys: String, CodingKey {
        case points, fresh
        case ageS = "age_s"
    }
}

struct BookHealth: Codable {
    let tokens: Int?
}

struct StoreStats: Codable {
    let snapshots: Int?
    let advice: Int?
    let windows: Int?
    let bytes: Int64?
}

struct MarketWindow: Codable, Identifiable {
    let slug: String?
    let asset: String?
    let openTs: Double?
    let closeTs: Double?
    let tRemaining: Double?
    /// Seconds until this window opens. The server sends it for every row; it is
    /// only meaningful while `preopen` is true, and it is what the "next market"
    /// section counts down to.
    let tOpen: Double?
    let preopen: Bool?
    let resolved: Bool?
    let snapshot: MarketSnapshot?

    var id: String { slug ?? "\(asset ?? "?")-\(openTs ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case slug, asset, preopen, resolved, snapshot
        case openTs = "open_ts"
        case closeTs = "close_ts"
        case tRemaining = "t_remaining"
        case tOpen = "t_open"
    }

    var intervalMinutes: Int {
        guard let openTs, let closeTs else { return 5 }
        return max(1, Int(((closeTs - openTs) / 60).rounded()))
    }

    var opensAt: Date? { openTs.map { Date(timeIntervalSince1970: $0) } }
    var closesAt: Date? { closeTs.map { Date(timeIntervalSince1970: $0) } }

    /// A market that has been discovered but has not started yet.
    ///
    /// The server filters closed and settled windows out of `/api/state`, so
    /// everything it sends is either open (`preopen == false`) or waiting to
    /// open. The flag appears at both levels — on the window and inside its
    /// snapshot — because the engine writes it in both places; reading either
    /// one is enough to classify the row.
    var isPreopen: Bool { preopen == true || snapshot?.preopen == true }

    /// Open right now and still unsettled — the only state the live board shows.
    ///
    /// The server already drops closed windows, but the client re-checks against
    /// the wall clock: a poll can land a second or two after a window closes, and
    /// a row with a negative countdown must never reach the screen even briefly.
    var isActivelyOpen: Bool { !isPreopen && (tRemaining ?? 0) > 0 }

    /// Seconds until this window opens, measured locally so the countdown keeps
    /// ticking between polls instead of freezing at the last server value.
    var secondsToOpen: Double? {
        guard let openTs else { return tOpen }
        return max(0, openTs - Date().timeIntervalSince1970)
    }

    /// The full window length in seconds, used to drive the countdown ring.
    var intervalSeconds: Double {
        guard let openTs, let closeTs else { return 300 }
        return max(1, closeTs - openTs)
    }
}

/// Snapshot fields are optional on purpose: the server emits `null` for
/// bid/ask while a book is still priming and for `beat` before the boundary
/// stamp lands. Decoding strictly would blank whole windows.
struct MarketSnapshot: Codable {
    let ts: Double?
    let slug: String?
    let asset: String?
    let spot: Double?
    let beat: Double?
    let sigma: Double?
    let pUp: Double?
    /// The book's own mid for UP, averaged across both sides server-side.
    /// Measured at Brier 0.126 against 0.234 for pUp on 1,822 held-out windows,
    /// so this is the number to trust when both are present.
    let pMarket: Double?
    let upBid: Double?
    let upAsk: Double?
    let downBid: Double?
    let downAsk: Double?
    let tRemaining: Double?
    let feed: String?
    let preopen: Bool?
    let beatSrc: String?
    let twap60: Double?
    let twapAgeS: Double?
    let interval: Double?
    let momentumBps: Double?
    let openTs: Double?
    let closeTs: Double?
    let edgeUp: Double?
    let edgeDown: Double?
    /// Resting size within 2c of each touch. Collected from 2026-11-03 and not
    /// yet used by any decision — on 75 windows the depth coefficient was not
    /// stable across sample halves, so it is context, never a trigger.
    let upDepthBid: Double?
    let upDepthAsk: Double?
    let downDepthBid: Double?
    let downDepthAsk: Double?
    /// Where 30s of taker money went across the pair: +1 all UP, -1 all DOWN.
    /// Per-token imbalance was useless here (takers almost always buy, so it
    /// pinned at 1.0); this cross-token version is the informative one.
    let flowSkew: Double?
    /// Recent volatility against the window's typical level; the engine uses it
    /// as a gate input, so it is shown rather than hidden.
    let volRatio: Double?
    /// The engine's own verdict for this window, when it emitted one.
    ///
    /// This is the authoritative answer to "is this a trade?". `edgeUp` and
    /// `edgeDown` are the model's arithmetic and are routinely positive while
    /// the engine stands down, because the model loses to the book on measured
    /// Brier. Absent means the engine said nothing this tick — not "go ahead".
    let advice: SignalAdvice?

    enum CodingKeys: String, CodingKey {
        case ts, slug, asset, spot, beat, sigma, feed, preopen, interval, twap60
        case advice
        case pUp = "p_up"
        case pMarket = "p_market"
        case upBid = "up_bid"
        case upAsk = "up_ask"
        case downBid = "down_bid"
        case downAsk = "down_ask"
        case tRemaining = "t_remaining"
        case beatSrc = "beat_src"
        case twapAgeS = "twap_age_s"
        case momentumBps = "momentum_bps"
        case openTs = "open_ts"
        case closeTs = "close_ts"
        case upDepthBid = "up_depth_bid"
        case upDepthAsk = "up_depth_ask"
        case downDepthBid = "down_depth_bid"
        case downDepthAsk = "down_depth_ask"
        case flowSkew = "flow_skew"
        case volRatio = "vol_ratio"
        case edgeUp = "edge_up"
        case edgeDown = "edge_down"
    }

    /// The book's mid for UP, falling back to the model only when the book is
    /// one-sided. This is what "fair value" means in this app: on 1,822 held-out
    /// observations the book scored Brier 0.1365 / 78.8% against 0.2335 / 58.7%
    /// for the model, and a blend optimiser set the model's weight to zero. So
    /// the model's number is shown as "Model", never as "Fair".
    var bookUp: Double? { pMarket ?? pUp }

    /// Spot minus price-to-beat, in basis points. Positive = currently ahead.
    var deltaBps: Double? {
        guard let spot, let beat, beat > 0 else { return nil }
        return (spot - beat) / beat * 10_000
    }

    /// The side with the better net edge, if either clears zero.
    var bestSide: String? {
        guard let u = edgeUp, let d = edgeDown else { return nil }
        if u <= 0 && d <= 0 { return nil }
        return u >= d ? "UP" : "DOWN"
    }

    var bestEdge: Double? {
        guard let u = edgeUp, let d = edgeDown else { return nil }
        let best = max(u, d)
        return best > 0 ? best : nil
    }

    /// Taker fee per share at a given contract price: 0.07 * p * (1 - p).
    static func fee(price: Double?) -> Double? {
        guard let price else { return nil }
        return 0.07 * price * (1 - price)
    }

    // MARK: Engine verdict

    /// Minimum raw edge we will still surface when the engine emitted nothing.
    ///
    /// 2c was never enough: the taker fee alone is 1.75c/share at p=0.50 both
    /// ways, and the round trip also pays the spread, so anything under ~4.5c is
    /// structurally unprofitable before the outcome is even considered. Measured
    /// on 3,926 resolved rows the model's edge is anti-predictive, so a bare
    /// board only earns a fallback card when the arithmetic clears the cost of
    /// trading it, not merely zero.
    static let fallbackEdgeFloor: Double = 0.045

    var advisedKind: String? { advice?.kind?.uppercased() }

    /// True only when the engine said to act. WATCH, AVOID and BID are notes,
    /// not instructions, and must never render as a trade.
    var adviceIsAction: Bool {
        guard let k = advisedKind else { return false }
        return k == "BUY" || k == "SELL"
    }

    /// The engine's side must agree with the side our own maths prefers, and
    /// both must still show a positive edge after the taker fee. A note that
    /// points the other way is not a confirmation, it is a contradiction.
    var adviceMatchesBestEdge: Bool {
        guard let a = advice,
              let adviceSide = a.side?.uppercased(),
              let best = bestSide?.uppercased(),
              adviceSide == best else { return false }
        if let ae = a.edge, let be = bestEdge { return ae > 0 && be > 0 }
        return true
    }

    /// A recommendation we are willing to present as a trade: the server emitted
    /// an actionable kind that lines up with the best edge.
    var serverValidatedTrade: Bool {
        advice != nil && adviceIsAction && adviceMatchesBestEdge
    }

    /// No engine verdict at all, but the arithmetic clears the cost of trading.
    ///
    /// Also requires a real two-sided book: without both asks there is no
    /// executable price, and the edge being computed from a one-sided quote is
    /// how a phantom card gets pinned to the top of the board.
    var fallbackTrade: Bool {
        advice == nil
            && upAsk != nil && downAsk != nil
            && (bestEdge ?? 0) >= Self.fallbackEdgeFloor
    }

    /// The single question the UI should ask before showing a plan.
    var isTradeable: Bool { serverValidatedTrade || fallbackTrade }

    /// Why there is no trade: the engine's own sentence when it gave one, then
    /// its vocabulary when it gave a verdict without a sentence.
    ///
    /// The previous version read `guard let e = bestEdge, e > 0 else { return nil }`
    /// and then returned nil on both paths, so it could only ever repeat the
    /// reason the card already read inline. A nil result is meaningful here — it
    /// tells the card to use its measured fallback copy — so the kind-based
    /// sentences below exist to keep the engine's own vocabulary in one place
    /// rather than duplicated in the view.
    var standDownReason: String? {
        if let r = advice?.reason, !r.isEmpty { return r }
        switch advisedKind {
        case "WATCH":
            return "The model and the book disagree and neither side clears the "
                 + "taker fee, so the correct position is flat."
        case "AVOID":
            return "The ask is above fair value once the taker fee is counted, "
                 + "so this is the classic cheap-looking trap."
        case "BID":
            return "A resting bid is the only positive-expectation entry here; "
                 + "taking at the ask is not."
        case "SELL":
            return "This is an exit signal — there is nothing to buy at this price."
        default:
            return nil
        }
    }
}

/// The engine's per-window verdict, mirrored from `Signal.to_dict()`.
///
/// Every field is optional: the server omits `advice` entirely on ticks where no
/// signal fired, and older builds omit fields this struct knows about. Decoding
/// strictly would blank the whole board, which is worse than a nil verdict.
struct SignalAdvice: Codable {
    let kind: String?
    let asset: String?
    let slug: String?
    let side: String?
    let price: Double?
    let modelP: Double?
    let edge: Double?
    let roi: Double?
    let breakeven: Double?
    let tRemaining: Double?
    let conf: String?
    let feed: String?
    let reason: String?
    let sizeShares: Int?
    let exitPrice: Double?
    let holdEv: Double?
    let ts: Double?
    let pMarket: Double?

    enum CodingKeys: String, CodingKey {
        case kind, asset, slug, side, price, edge, roi, breakeven, conf, feed,
             reason, ts
        case modelP = "model_p"
        case tRemaining = "t_remaining"
        case sizeShares = "size_shares"
        case exitPrice = "exit_price"
        case holdEv = "hold_ev"
        case pMarket = "p_market"
    }
}

// MARK: - /api/advice

struct Advice: Codable, Identifiable {
    let id: Int?
    let ts: Double?
    let slug: String?
    let asset: String?
    let kind: String?
    let side: String?
    let price: Double?
    let modelP: Double?
    let edge: Double?
    let roi: Double?
    let breakeven: Double?
    let tRemaining: Double?
    let conf: String?
    let feed: String?
    let reason: String?
    let sizeShares: Int?
    let exitPrice: Double?
    let holdEv: Double?
    let outcome: String?

    var uid: String { "\(id ?? 0)-\(slug ?? "")-\(ts ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case id, ts, slug, asset, kind, side, price, edge, roi, breakeven,
             conf, feed, reason, outcome
        case modelP = "model_p"
        case tRemaining = "t_remaining"
        case sizeShares = "size_shares"
        case exitPrice = "exit_price"
        case holdEv = "hold_ev"
    }

    var date: Date? { ts.map { Date(timeIntervalSince1970: $0) } }

    var isExit: Bool {
        let k = (kind ?? "").uppercased()
        return k.contains("SELL") || k.contains("EXIT") || k.contains("TRIM")
    }

    /// A WATCH row is information, not an instruction: the model and the book
    /// disagree, and the book is the better forecaster. It must never be
    /// grouped with executable buys.
    var isWatch: Bool { (kind ?? "").uppercased() == "WATCH" }

    /// Something the engine would actually have you pay for.
    var isActionable: Bool {
        guard !isExit, !isWatch else { return false }
        let k = (kind ?? "").uppercased()
        return k.contains("BUY") || k.contains("BID")
    }

    var tint: Color {
        let k = (kind ?? "").uppercased()
        if k == "WATCH" { return Palette.warn }
        switch k {
        case "BUY", "BID": return Palette.accent
        default:           return isExit ? Palette.warn : Palette.dim
        }
    }
}

// MARK: - /api/scorecard

struct Scorecard: Codable {
    let windowDays: Int?
    let n: Int?
    let hitRate: Double?
    let byConf: [String: ConfStat]?

    enum CodingKeys: String, CodingKey {
        case n
        case windowDays = "window_days"
        case hitRate = "hit_rate"
        case byConf = "by_conf"
    }

    /// Stable ordering for display: most-advised bucket first.
    var orderedBuckets: [(key: String, stat: ConfStat)] {
        (byConf ?? [:])
            .map { (key: $0.key, stat: $0.value) }
            .sorted { ($0.stat.n ?? 0) > ($1.stat.n ?? 0) }
    }
}

struct ConfStat: Codable {
    let n: Int?
    let good: Int?
    let avgPrice: Double?
    let hitRate: Double?

    enum CodingKeys: String, CodingKey {
        case n, good
        case avgPrice = "avg_price"
        case hitRate = "hit_rate"
    }
}

// MARK: - /api/review

/// The server's retrospective: which markets already settled, and the measured
/// lessons those settlements taught.
///
/// The board deliberately serves only markets you can still act on. Everything
/// settled lands here instead, so the record stays complete without the live
/// list reading as a column of missed chances. Every lesson carries the sample
/// size it was measured on and the change it makes to the next call — a lesson
/// without an `n` would be an assertion, and this app does not assert.
struct ReviewResponse: Codable {
    let generatedTs: Double?
    let ttlS: Double?
    let windowDays: Int?
    let counts: ReviewCounts?
    let recent: [ReviewMarket]?
    let lessons: [ReviewLesson]?
    /// The server's own sentence tying the lessons to the next prediction.
    let influence: String?
    let scorecard: ReviewScorecard?
    let modelVsBook: ModelVsBook?
    let slices: ReviewSlices?

    enum CodingKeys: String, CodingKey {
        case counts, recent, lessons, influence, scorecard, slices
        case generatedTs = "generated_ts"
        case ttlS = "ttl_s"
        case windowDays = "window_days"
        case modelVsBook = "model_vs_book"
    }

    var generatedAt: Date? {
        generatedTs.map { Date(timeIntervalSince1970: $0) }
    }

    var lessonsList: [ReviewLesson] { lessons ?? [] }
    var recentList: [ReviewMarket] { recent ?? [] }

    /// Share of settled markets the book called correctly, when it was graded.
    var bookAccuracy: Double? {
        guard let c = counts, let right = c.bookRight, let n = c.resolved, n > 0 else { return nil }
        return Double(right) / Double(n)
    }

    /// Share the model called correctly over the same rows. The comparison is
    /// paired, so these two numbers are always on the same sample.
    var modelAccuracy: Double? {
        guard let c = counts, let right = c.modelRight, let n = c.resolved, n > 0 else { return nil }
        return Double(right) / Double(n)
    }
}

struct ReviewCounts: Codable {
    let resolved: Int?
    let modelRight: Int?
    let bookRight: Int?
    let advised: Int?
    let adviceHits: Int?
    let disagreements: Int?

    enum CodingKeys: String, CodingKey {
        case resolved, advised, disagreements
        case modelRight = "model_right"
        case bookRight = "book_right"
        case adviceHits = "advice_hits"
    }
}

/// One settled market and what the engine had said about it.
///
/// `kind`/`side` are the last advice emitted before the close, so a `WATCH` row
/// means the engine declined and the outcome went whichever way the book called
/// it. `hit` is only set for a BUY, because only a buy has a hit to record.
struct ReviewMarket: Codable, Identifiable {
    let slug: String?
    let asset: String?
    let closeTs: Double?
    let outcome: String?
    let kind: String?
    let side: String?
    let price: Double?
    let modelP: Double?
    let pMarket: Double?
    let conf: String?
    let modelRight: Bool?
    let bookRight: Bool?
    let hit: Bool?
    let pnlCents: Double?

    var id: String { "\(slug ?? "?")-\(closeTs ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case slug, asset, outcome, kind, side, price, conf, hit
        case closeTs = "close_ts"
        case modelP = "model_p"
        case pMarket = "p_market"
        case modelRight = "model_right"
        case bookRight = "book_right"
        case pnlCents = "pnl_cents"
    }

    var closedAt: Date? { closeTs.map { Date(timeIntervalSince1970: $0) } }

    var outcomeIsUp: Bool? {
        guard let o = outcome?.uppercased(), o == "UP" || o == "DOWN" else { return nil }
        return o == "UP"
    }

    /// True when the engine told the reader to buy this market.
    var wasAdvice: Bool {
        guard let k = kind?.uppercased() else { return false }
        return k == "BUY" || k == "SELL"
    }

    var intervalMinutes: Int? {
        guard let slug else { return nil }
        // Slugs read <asset>-updown-<minutes>m-<epoch>; the length is in the name.
        let parts = slug.split(separator: "-")
        for part in parts where part.hasSuffix("m") {
            let digits = part.dropLast()
            if let m = Int(digits) { return m }
        }
        return nil
    }
}

struct ReviewLesson: Codable, Identifiable {
    let id: String
    let title: String?
    let statement: String?
    let implication: String?
    let n: Int?
}

/// The retrospective scorecard, reduced to what the review renders. The server
/// sends the full scorecard elsewhere; only the headline is repeated here.
struct ReviewScorecard: Codable {
    let n: Int?
    let hitRate: Double?
    let byConf: [String: ConfStat]?

    enum CodingKeys: String, CodingKey {
        case n
        case hitRate = "hit_rate"
        case byConf = "by_conf"
    }
}

/// Paired Brier comparison. Both scores are computed on the same rows, so the
/// gap between them is a like-for-like statement rather than two separate runs.
struct ModelVsBook: Codable {
    let n: Int?
    let windowDays: Int?
    let model: BrierStat?
    let book: BrierStat?
    let byGap: [String: GapStat]?
    let disagreements: GapDisagreements?

    enum CodingKeys: String, CodingKey {
        case n, model, book, disagreements
        case windowDays = "window_days"
        case byGap = "by_gap"
    }

    /// Ordered narrow-gap-first so the table reads as a gradient of disagreement.
    ///
    /// Returned as `GapRow` rather than a tuple because Swift key paths cannot
    /// address tuple elements, and `ForEach` needs an identifier.
    var orderedGaps: [GapRow] {
        let order = ["0.00-0.05", "0.05-0.10", "0.10-0.20", "0.20-0.35", "0.35-1.01"]
        let dict = byGap ?? [:]
        return order.compactMap { key in
            guard let stat = dict[key] else { return nil }
            return GapRow(id: key, stat: stat)
        }
    }
}

/// Realised, fee-inclusive EV of BUY advice for one asset/interval slice.
///
/// The server reports the spread because the aggregate hides it: every slice
/// loses over the recorded history, but the worst is roughly five times the
/// best. Showing cents per share rather than a percentage keeps the number
/// comparable to the fee, which is the thing that decides whether any of it
/// could ever work.
struct SliceCell: Codable {
    let n: Int?
    let hitRate: Double?
    let evCents: Double?
    let seCents: Double?

    enum CodingKeys: String, CodingKey {
        case n
        case hitRate = "hit_rate"
        case evCents = "ev_cents"
        case seCents = "se_cents"
    }

    /// Whether the estimate is separated from zero at two standard errors.
    ///
    /// A slice that spans zero is not an edge in either direction, and the UI
    /// must not colour it as though it were. In the recorded data every slice
    /// is negative but most are within two SE of flat.
    var isDistinguishable: Bool {
        guard let ev = evCents, let se = seCents, se > 0 else { return false }
        return abs(ev) > 2 * se
    }

    var evLabel: String {
        guard let ev = evCents else { return "—" }
        return String(format: "%+.2fc", ev)
    }
}

struct ReviewSlices: Codable {
    let windowDays: Int?
    let overall: SliceCell?
    let byAsset: [String: SliceCell]?
    let byInterval: [String: SliceCell]?
    let byAssetInterval: [String: SliceCell]?

    enum CodingKeys: String, CodingKey {
        case overall
        case windowDays = "window_days"
        case byAsset = "by_asset"
        case byInterval = "by_interval"
        case byAssetInterval = "by_asset_interval"
    }

    /// Worst first: the useful reading is which slice is dragging the total.
    var orderedPairs: [SliceRow] {
        (byAssetInterval ?? [:])
            .map { SliceRow(id: $0.key, cell: $0.value) }
            .sorted { ($0.cell.evCents ?? 0) < ($1.cell.evCents ?? 0) }
    }
}

struct SliceRow: Identifiable {
    let id: String
    let cell: SliceCell
}

/// One disagreement bucket, keyed by the label the server uses.
struct GapRow: Identifiable {
    let id: String
    let stat: GapStat
}

struct BrierStat: Codable {
    let brier: Double?
    let acc: Double?
}

struct GapStat: Codable {
    let n: Int?
    let modelWinRate: Double?
    let bookWinRate: Double?

    enum CodingKeys: String, CodingKey {
        case n
        case modelWinRate = "model_win_rate"
        case bookWinRate = "book_win_rate"
    }
}

struct GapDisagreements: Codable {
    let n: Int?
    let modelWinRate: Double?

    enum CodingKeys: String, CodingKey {
        case n
        case modelWinRate = "model_win_rate"
    }
}

// MARK: - /api/exec

struct ExecStatus: Codable {
    let attached: Bool?
    let enabled: Bool?
    let dryRun: Bool?
    let ready: Bool?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case attached, enabled, ready, reason
        case dryRun = "dry_run"
    }
}
