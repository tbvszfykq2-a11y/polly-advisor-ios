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
        let side = (s?.bestSide ?? "UP").uppercased()
        let isUp = side == "UP"
        let ask = isUp ? s?.upAsk : s?.downAsk
        let bid = isUp ? s?.upBid : s?.downBid
        let fair = isUp ? s?.pUp : s?.pUp.map { 1 - $0 }
        let edge = isUp ? s?.edgeUp : s?.edgeDown
        let feeEntry = ask.map { 0.07 * $0 * (1 - $0) } ?? 0

        Panel(padding: 15, highlight: true) {
            VStack(spacing: 12) {
                // Pinned identity
                HStack(spacing: 9) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.warn)
                    MicroLabel(
                        text: (edge ?? 0) > 0 ? "Best trade now" : "Best market · no edge",
                        tint: (edge ?? 0) > 0 ? Palette.warn : Palette.dim
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
                        Text("\(AssetStyle.ticker(window.asset ?? s?.asset)) · \(Fmt.cents(ask)) entry · \(Fmt.pct(fair)) fair")
                            .font(.mono(9.5))
                            .foregroundStyle(Palette.faint)
                    }
                    Spacer(minLength: 0)
                }

                ProbBar(fair: fair ?? 0.5, market: ask)
                    .animation(Motion.value, value: fair ?? 0.5)

                if let entry = ask, entry > 0 {
                    if (edge ?? 0) <= 0 {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.down)
                            Text("No edge at this price — stand down. "
                                 + "Buying here loses \(Fmt.signedCents(-(edge ?? 0))) per share "
                                 + "after the taker fee, so the correct size is zero.")
                                .font(.label(10.5))
                                .foregroundStyle(Palette.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    plan(side: side, ask: entry, bid: bid, fair: fair ?? 0,
                         edge: edge ?? 0, feeEntry: feeEntry, snapshot: s)
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

    // MARK: Plan

    @ViewBuilder
    private func plan(side: String, ask: Double, bid: Double?, fair: Double,
                      edge: Double, feeEntry: Double, snapshot s: MarketSnapshot?) -> some View {
        let target = exitTarget(ask: ask, fair: fair)
        let feeExit = 0.07 * target * (1 - target)
        let perShareExit = target - ask - feeEntry - feeExit
        let shares = ask > 0 ? Int((Self.stakeUSD / ask).rounded(.down)) : 0
        let cost = Double(shares) * ask
        let profitAtTarget = Double(shares) * perShareExit
        let holdEV = Double(shares) * (fair - ask - feeEntry)
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
                        ? "The model prices it at \(Fmt.pct(fair)); the ask is "
                            + "\(Fmt.signedCents(edge)) below fair after fees."
                        : "The model prices it at \(Fmt.pct(fair)); the ask is "
                            + "\(Fmt.signedCents(-edge)) above fair after fees.")
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
