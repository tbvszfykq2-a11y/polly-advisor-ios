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
    let preopen: Bool?
    let resolved: Bool?
    let snapshot: MarketSnapshot?

    var id: String { slug ?? "\(asset ?? "?")-\(openTs ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case slug, asset, preopen, resolved, snapshot
        case openTs = "open_ts"
        case closeTs = "close_ts"
        case tRemaining = "t_remaining"
    }

    var intervalMinutes: Int {
        guard let openTs, let closeTs else { return 5 }
        return max(1, Int(((closeTs - openTs) / 60).rounded()))
    }

    var opensAt: Date? { openTs.map { Date(timeIntervalSince1970: $0) } }
    var closesAt: Date? { closeTs.map { Date(timeIntervalSince1970: $0) } }

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

    enum CodingKeys: String, CodingKey {
        case ts, slug, asset, spot, beat, sigma, feed, preopen, interval, twap60
        case pUp = "p_up"
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
        case edgeUp = "edge_up"
        case edgeDown = "edge_down"
    }

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

    var tint: Color {
        switch (kind ?? "").uppercased() {
        case "BUY": return Palette.accent
        default:    return isExit ? Palette.warn : Palette.dim
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
