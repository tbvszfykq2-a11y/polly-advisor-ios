import SwiftUI

// MARK: - Next market

/// The forecast for a window that has not opened yet.
///
/// Deliberately not a trade card. Before a window opens there is no opening
/// TWAP, so the engine prices it from momentum and the book rather than from the
/// settlement rule that will actually decide it. The card shows the forecast and
/// names what it is missing, instead of dressing the number up as an entry.
struct NextMarketCard: View {
    let window: MarketWindow

    private var snap: MarketSnapshot? { window.snapshot }

    /// The model's read and the book's read, side by side. They are separate
    /// estimators on purpose: on this tape they disagree often, and the book has
    /// won that argument far more often than the model has.
    private var modelP: Double? { snap?.pUp }
    private var bookP: Double? { snap?.pMarket }

    private var modelSide: String? {
        guard let p = modelP else { return nil }
        return p >= 0.5 ? "UP" : "DOWN"
    }

    private var bookSide: String? {
        guard let p = bookP else { return nil }
        return p >= 0.5 ? "UP" : "DOWN"
    }

    private var agree: Bool? {
        guard let a = modelSide, let b = bookSide else { return nil }
        return a == b
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AssetMark(asset: window.asset, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(AssetStyle.ticker(window.asset))
                                .font(.label(13.5, .bold))
                                .foregroundStyle(Palette.text)
                            IntervalChip(minutes: window.intervalMinutes)
                        }
                        Text("not open yet")
                            .font(.mono(9))
                            .foregroundStyle(Palette.faint)
                    }
                    Spacer(minLength: 4)
                    OpensInCountdown(opensAt: window.opensAt, fallback: window.tOpen)
                }

                Rule()

                HStack(spacing: 0) {
                    Metric(label: "Model", value: Fmt.pct(modelP), size: 15)
                    Metric(label: "Book", value: Fmt.pct(bookP), size: 15, tint: Palette.accent)
                    Metric(
                        label: "Model side",
                        value: modelSide ?? "—",
                        size: 15,
                        tint: modelSide == "UP" ? Palette.up
                            : (modelSide == "DOWN" ? Palette.down : Palette.faint)
                    )
                }

                Text(note)
                    .font(.label(10.5))
                    .foregroundStyle(agree == false ? Palette.warn.opacity(0.9) : Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The sentence that stops the model's number being read as a trade.
    private var note: String {
        guard let a = modelSide, let b = bookSide else {
            return "No book quote yet, so this is momentum alone. The forecast firms up "
                + "once the book opens."
        }
        if a == b {
            return "Model and book agree on \(a). The book is the more accurate of the two "
                + "on measured settlements, so agreement is the only case where the "
                + "model's number is worth much."
        }
        return "Model says \(a), book says \(b). The book has won these disagreements on "
            + "this tape, so the model's side is the weaker read — not an opportunity."
    }
}

// MARK: - Opens-in countdown

/// Counts down to a future timestamp on a 1 s timeline, so the number keeps
/// moving between polls instead of freezing and then jumping.
struct OpensInCountdown: View {
    let opensAt: Date?
    /// Server value, used only when the window carries no absolute open time.
    let fallback: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = remainingSeconds(at: context.date)
            VStack(alignment: .trailing, spacing: 1) {
                Text("OPENS IN")
                    .font(.label(7.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.faint)
                Text(Fmt.clock(remaining))
                    .font(.mono(14, .semibold))
                    .foregroundStyle(remaining < 60 ? Palette.warn : Palette.dim)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
        }
    }

    /// Derived from the absolute open time so every tick is exact. The server's
    /// `t_open` is a snapshot of the same quantity and would freeze between
    /// polls, which is the jitter this view exists to remove.
    private func remainingSeconds(at date: Date) -> Double {
        if let opensAt { return max(0, opensAt.timeIntervalSince(date)) }
        return max(0, fallback ?? 0)
    }
}
