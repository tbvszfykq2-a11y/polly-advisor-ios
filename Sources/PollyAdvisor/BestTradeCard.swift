import SwiftUI
import UIKit

/// The single best trade on the board, pinned above the sections.
///
/// Every number here is derived from the advisor's own snapshot: the ask, the
/// model probability and the taker fee. Nothing is invented — if the book has
/// no quote the card says so instead of showing a plan you cannot execute.
struct BestTradeCard: View {
    let window: MarketWindow
    @EnvironmentObject private var model: AppModel

    /// Illustrative stake. The engine caps real size at $100/window; this is a
    /// reference point so the plan has actual money attached to it.
    private static let stakeUSD: Double = 50

    var body: some View {
        let s = window.snapshot
        // The server's verdict decides the side when it gave one. Falling back to
        // `bestSide` here was the bug: the engine answers WATCH precisely when the
        // model and the book disagree, so the local edge pointed one way while the
        // advisor had already declined to trade at all.
        let validated = s?.serverValidatedTrade == true
        let side = ((validated ? s?.advice?.side : nil) ?? s?.bestSide ?? "UP").uppercased()
        let isUp = side == "UP"
        let ask = isUp ? s?.upAsk : s?.downAsk
        let bid = isUp ? s?.upBid : s?.downBid
        let modelP = isUp ? s?.pUp : s?.pUp.map { 1 - $0 }
        let bookP = isUp ? s?.bookUp : s?.bookUp.map { 1 - $0 }
        // Prefer the engine's own edge when it endorsed the trade; the raw
        // arithmetic is only a stand-in for a silent server.
        let edge = (validated ? s?.advice?.edge : nil) ?? (isUp ? s?.edgeUp : s?.edgeDown)
        let feeEntry = ask.map { 0.07 * $0 * (1 - $0) } ?? 0
        let tradeable = s?.isTradeable == true
        let advisedKind = s?.advisedKind

        Panel(padding: 15, highlight: tradeable) {
            VStack(spacing: 12) {
                // Pinned identity. The label states whose call this is: an endorsed
                // server signal, a bare-arithmetic fallback, or the engine saying
                // no. Conflating those was how the card ended up advertising trades
                // the advisor had declined.
                HStack(spacing: 9) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.warn)
                    MicroLabel(
                        text: validated ? "Server trade"
                            : (tradeable ? "Best trade now"
                               : (advisedKind.map { "Server: \($0)" }
                                  ?? "Best market · no trade")),
                        tint: tradeable ? Palette.warn : Palette.dim
                    )
                    Spacer(minLength: 4)
                    LiveCountdown(
                        closesAt: window.closesAt,
                        fallback: s?.tRemaining ?? window.tRemaining ?? 0,
                        total: window.intervalSeconds
                    )
                }

                HStack(spacing: 10) {
                    AssetMark(asset: window.asset ?? s?.asset, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            SideChip(text: side,
                                     tint: isUp ? Palette.up : Palette.down,
                                     filled: true)
                            IntervalChip(minutes: window.intervalMinutes)
                            EdgeBadge(edge: edge)
                        }
                        // "Model", not "fair": on 1,822 held-out windows the model
                        // scored Brier 0.234 against 0.137 for the book's mid, so the
                        // calibrated reference is the book and both are shown.
                        Text("\(AssetStyle.ticker(window.asset ?? s?.asset)) · \(Fmt.cents(ask)) ask · \(Fmt.pct(modelP)) model · \(Fmt.pct(bookP)) book")
                            .font(.mono(9.5))
                            .foregroundStyle(Palette.faint)
                    }
                    Spacer(minLength: 0)
                }

                // Trust line: what actually decides this contract, and how fresh
                // the quote beside it is. Kalshi's lesson is that visible
                // regulation builds trust; here the "regulation" is the
                // settlement source. Burying "Chainlink TWAP-60" in a details
                // sheet leaves the user unsure what they are betting on.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Palette.faint)
                    Text("resolves on Chainlink TWAP-60 · quote \(quoteAge(s))")
                        .font(.mono(8.5))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                ProbBar(fair: modelP ?? 0.5, market: ask)
                    .animation(Motion.value, value: modelP ?? 0.5)

                if let entry = ask, entry > 0 {
                    if !tradeable {
                        // The gate, not the arithmetic. A positive edgeUp is not
                        // permission to trade: the engine answers WATCH on exactly
                        // those ticks because the book is the better forecaster.
                        // Showing a copyable "action: BUY" sheet here was the one
                        // place the app still told the user what to buy while the
                        // advisor had declined.
                        standDown(edge: edge ?? 0, modelP: modelP, bookP: bookP,
                                  s: s, advisedKind: advisedKind)
                    } else {
                        plan(side: side, ask: entry, bid: bid, modelP: modelP ?? 0,
                             bookP: bookP, edge: edge ?? 0, feeEntry: feeEntry, snapshot: s)
                    }
                } else {
                    // No quote means no executable plan. Say it plainly.
                    Text("No book quote on this market yet, so there is nothing to buy. "
                         + "The advisor will price it once the book is live.")
                        .font(.label(11))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Stand down

    /// The honest state when no side clears the fee hurdle.
    ///
    /// Deliberately contains no plan and no copy button: there is nothing to
    /// execute. What it does contain is the one useful thing left — how far the
    /// model and the book disagree, and which way the evidence points. The book
    /// has measured better (Brier 0.1365 vs 0.2335), so when they disagree the
    /// card says so and sides with the book rather than dressing the model's
    /// number up as an opportunity.
    @ViewBuilder
    private func standDown(edge: Double, modelP: Double?, bookP: Double?,
                           s: MarketSnapshot?, advisedKind: String?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.down)
                Text(standDownHeadline(advisedKind))
                    .font(.label(11.5, .semibold))
                    .foregroundStyle(Palette.text)
            }

            // The engine's own sentence when it gave one. This is the whole point
            // of surfacing advice: the reason is written server-side with both
            // probabilities in hand, so it beats anything the client can infer.
            // `standDownReason` owns that lookup plus the kind-based fallback, so
            // the view does not have to re-implement the precedence.
            if let reason = s?.standDownReason {
                Text(reason)
                    .font(.label(10.5))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The ask is \(Fmt.signedCents(-edge)) per share above the model's "
                     + "probability after the taker fee, so the correct size is zero. "
                     + "Measured over 12,816 resolved rows, taker buying lost 1.8¢/share — "
                     + "standing down is the expected-value answer, not a missed trade.")
                    .font(.label(10.5))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The divergence is the information: what the model thinks vs what
            // the book is actually pricing. This is the reason to keep watching
            // instead of closing the app.
            if let m = modelP, let b = bookP, abs(m - b) >= 0.03 {
                Rule()
                VStack(alignment: .leading, spacing: 4) {
                    MicroLabel(text: "Where the two disagree", tint: Palette.faint)
                    HStack(spacing: 0) {
                        Metric(label: "Model", value: Fmt.pct(m), size: 13)
                        Metric(label: "Book", value: Fmt.pct(b), size: 13,
                               tint: Palette.accent)
                        Metric(label: "Gap", value: Fmt.signedCents(b - m), size: 13,
                               tint: Palette.dim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("The book is the better forecaster on measured Brier, so this "
                     + "gap is the model's error until the tape says otherwise. "
                     + "Nothing here is worth paying the fee to act on.")
                    .font(.mono(9.5))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // What would change the answer — a concrete trigger, not a tease.
            if let m = modelP {
                let watchedSide = ((s?.advice?.side ?? s?.bestSide) ?? "UP").uppercased()
                let watchedAsk = watchedSide == "UP" ? s?.upAsk : s?.downAsk
                if let watchedAsk, watchedAsk > 0 {
                    let feeAtFair = feeAt(m)
                    let trigger = max(0.0, m - feeAtFair)
                    Rule()
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "arrow.down.right.circle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.warn)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("What would change it")
                                .font(.label(11, .semibold))
                                .foregroundStyle(Palette.text)
                            Text("A buy only clears the fee if the ask falls to about "
                                 + "\(Fmt.cents(trigger)) or the model's probability rises "
                                 + "above \(Fmt.pct(watchedAsk + feeAt(watchedAsk))). Until "
                                 + "then the correct position is flat.")
                                .font(.label(10.5))
                                .foregroundStyle(Palette.faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Headline for the no-trade state, in the engine's vocabulary.
    ///
    /// "No edge" was the wrong wording when the engine had actively decided the
    /// book was right: the card read as though the maths had simply not fired.
    /// Naming the verdict tells the reader who made the call.
    private func standDownHeadline(_ advisedKind: String?) -> String {
        switch advisedKind {
        case "WATCH":
            return "No trade — the book disagrees with the model."
        case "AVOID":
            return "No trade — the fee is not covered at this price."
        case "BID":
            return "No taker trade — a resting bid is the only +EV entry."
        case "SELL":
            return "Exit signal only — nothing to buy here."
        default:
            return "No edge at this price — stand down."
        }
    }

    private func feeAt(_ price: Double) -> Double { 0.07 * price * (1 - price) }

    /// How old the quote in the header is. The board polls on a timer, so a
    /// stale quote is a real risk: the edge may already be gone. Saying "3s ago"
    /// is the cheapest possible trust signal and costs one subtraction.
    private func quoteAge(_ s: MarketSnapshot?) -> String {
        guard let ts = s?.ts, ts > 0 else { return "—" }
        let age = Date().timeIntervalSince1970 - ts
        if age < 0 { return "now" }
        if age < 2 { return "just now" }
        if age < 60 { return "\(Int(age))s ago" }
        return "\(Int(age / 60))m ago"
    }

    // MARK: Plan

    @ViewBuilder
    private func plan(side: String, ask: Double, bid: Double?, modelP: Double,
                      bookP: Double?, edge: Double, feeEntry: Double,
                      snapshot s: MarketSnapshot?) -> some View {
        // Target off the book's mid, not the model's: it is the better-calibrated
        // number and it is also where a resting sell would actually clear.
        let target = exitTarget(ask: ask, fair: bookP ?? modelP)
        let feeExit = 0.07 * target * (1 - target)
        let perShareExit = target - ask - feeEntry - feeExit
        let shares = ask > 0 ? Int((Self.stakeUSD / ask).rounded(.down)) : 0
        let cost = Double(shares) * ask
        let profitAtTarget = Double(shares) * perShareExit
        // Hold EV against the book's mid when we have it. For a taker entry this
        // is negative by construction (half the spread plus the fee), which is the
        // honest read: the edge above is the model's, and the model loses to the book.
        let holdEV = Double(shares) * ((bookP ?? modelP) - ask - feeEntry)
        let breakeven = ask + feeEntry

        VStack(spacing: 10) {
            Rule()

            // The three numbers that decide the trade.
            HStack(spacing: 0) {
                Metric(label: "Enter at", value: Fmt.cents(ask), size: 15)
                Metric(label: "Exit at", value: Fmt.cents(target), size: 15, tint: Palette.up)
                Metric(label: "Breakeven", value: Fmt.cents(breakeven), size: 15,
                       tint: Palette.dim)
            }

            Rule()

            VStack(alignment: .leading, spacing: 7) {
                step(1,
                     edge > 0 ? "Buy \(side) at \(Fmt.cents(ask)) or better."
                              : "Do not buy \(side) at \(Fmt.cents(ask)).",
                     edge > 0
                        ? "The model prices it at \(Fmt.pct(modelP)); the ask is "
                            + "\(Fmt.signedCents(edge)) below that after fees."
                        : "The model prices it at \(Fmt.pct(modelP)); the ask is "
                            + "\(Fmt.signedCents(-edge)) above that after fees.")
                step(2, "Sell into \(Fmt.cents(target)) with a limit order.",
                     "That is \(Fmt.signedCents(perShareExit))/share on \(shares) shares "
                     + "≈ \(money(profitAtTarget)).")
                step(3, "If it has not filled by T-60s, take the bid.",
                     "Once the settlement window opens the TWAP freezes and this edge "
                     + "is gone — holding past that is a coin flip, not a trade.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rule()

            HStack(spacing: 0) {
                Metric(label: "Stake", value: money(cost), size: 13)
                Metric(label: "Shares", value: "\(shares)", size: 13)
                Metric(label: "At target", value: money(profitAtTarget), size: 13,
                       tint: profitAtTarget > 0 ? Palette.up : Palette.down)
                Metric(label: "Hold EV", value: money(holdEV), size: 13,
                       tint: holdEV > 0 ? Palette.dim : Palette.down)
            }

            Text(timingNote(s, edge: edge))
                .font(.mono(9.5))
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = sheet(side: side, ask: ask, target: target,
                                                    shares: shares, cost: cost,
                                                    profit: profitAtTarget)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Copy this plan", systemImage: "doc.on.doc")
                    .font(.label(12, .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.up.opacity(0.14))
                    )
            }
            .foregroundStyle(Palette.up)
        }
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.mono(9, .bold))
                .foregroundStyle(Palette.bg)
                .frame(width: 15, height: 15)
                .background(Circle().fill(Palette.dim))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.label(11.5, .semibold))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.label(10.5))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Where to take profit: the model's fair value, but never below a small
    /// margin over the ask and never absurdly near $1.
    private func exitTarget(ask: Double, fair: Double) -> Double {
        min(0.99, max(ask + 0.02, fair))
    }

    private func timingNote(_ s: MarketSnapshot?, edge: Double) -> String {
        let t = s?.tRemaining ?? 0
        if (s?.twapAgeS ?? 0) > 8 {
            return "Feed is stale — re-check before acting."
        }
        if t <= 60 {
            return "Settlement window open: edge decays by the second."
        }
        if t <= 120 {
            return "Under two minutes left — enter only if still above breakeven."
        }
        return "Edge is widest this far from the close and narrows as the window matures."
    }

    private func money(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    private func sheet(side: String, ask: Double, target: Double,
                       shares: Int, cost: Double, profit: Double) -> String {
        """
        POLLY ADVISOR — BEST TRADE
        market: \(window.slug ?? "—")  (\(window.intervalMinutes)m)
        action: BUY \(side)
        entry:  \(Fmt.cents(ask)) (limit, do not chase)
        exit:   sell limit at \(Fmt.cents(target))
        size:   \(shares) shares ≈ \(money(cost)) (at a $\(Int(Self.stakeUSD)) stake)
        target profit: \(money(profit))
        fallback: if unfilled by T-60s, sell into the bid.
        """
    }
}
