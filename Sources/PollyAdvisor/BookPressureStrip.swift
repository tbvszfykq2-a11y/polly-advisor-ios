import SwiftUI

/// Live book pressure: resting depth either side of the touch, and where the
/// last 30 seconds of taker money went.
///
/// This is deliberately read-only context, not a trigger. On the 75 windows
/// recorded so far the depth coefficient did not survive a split-half check and
/// the flow coefficient, while sign-stable, never reached significance in either
/// half. The strip exists so the number is visible and falsifiable rather than
/// buried in a database; nothing in the app ranks or recommends on it.
struct BookPressureStrip: View {
    let window: MarketWindow

    private var snap: MarketSnapshot? { window.snapshot }

    private var hasData: Bool {
        guard let s = snap else { return false }
        return s.flowSkew != nil || (s.upDepthBid ?? 0) > 0 || (s.downDepthBid ?? 0) > 0
    }

    var body: some View {
        if hasData, let s = snap {
            Panel {
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeader(title: "Book pressure", detail: skewDetail(s))
                    Rule()
                    row(label: "UP", bid: s.upDepthBid, ask: s.upDepthAsk,
                        tint: Palette.up)
                    row(label: "DOWN", bid: s.downDepthBid, ask: s.downDepthAsk,
                        tint: Palette.down)
                    skewBar(s)
                    Text(explanation(s))
                        .font(.mono(8.5))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: rows

    /// Bid and ask depth as a two-sided bar: the split is what matters, not the
    /// absolute size, because each market's book is scaled differently.
    private func row(label: String, bid: Double?, ask: Double?, tint: Color) -> some View {
        let b = max(bid ?? 0, 0)
        let a = max(ask ?? 0, 0)
        let total = b + a
        let share = total > 0 ? b / total : 0.5
        return HStack(spacing: 8) {
            Text(label)
                .font(.mono(9))
                .foregroundStyle(Palette.dim)
                .frame(width: 38, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18))
                    Capsule()
                        .fill(tint.opacity(0.75))
                        .frame(width: max(2, w * share))
                        .animation(Motion.value, value: share)
                }
            }
            .frame(height: 5)
            Text(depthLabel(b, a))
                .font(.mono(8.5))
                .foregroundStyle(Palette.faint)
                .frame(width: 96, alignment: .trailing)
        }
    }

    private func depthLabel(_ bid: Double, _ ask: Double) -> String {
        if bid <= 0 && ask <= 0 { return "no resting size" }
        return String(format: "%.0f bid / %.0f ask", bid, ask)
    }

    /// A centred needle: left is taker selling into DOWN, right is buying UP.
    private func skewBar(_ s: MarketSnapshot) -> some View {
        let skew = min(1, max(-1, s.flowSkew ?? 0))
        return HStack(spacing: 8) {
            Text("flow")
                .font(.mono(9))
                .foregroundStyle(Palette.dim)
                .frame(width: 38, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                let mid = w / 2
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05))
                    Rectangle()
                        .fill(Palette.faint.opacity(0.55))
                        .frame(width: 1)
                        .offset(x: mid)
                    if skew >= 0 {
                        Capsule()
                            .fill(Palette.up.opacity(0.8))
                            .frame(width: max(2, mid * skew))
                            .offset(x: mid)
                            .animation(Motion.value, value: skew)
                    } else {
                        Capsule()
                            .fill(Palette.down.opacity(0.8))
                            .frame(width: max(2, mid * -skew))
                            .offset(x: mid - mid * -skew)
                            .animation(Motion.value, value: skew)
                    }
                }
            }
            .frame(height: 5)
            Text(flowLabel(s))
                .font(.mono(8.5))
                .foregroundStyle(Palette.faint)
                .frame(width: 96, alignment: .trailing)
        }
    }

    // MARK: labels

    private func skewDetail(_ s: MarketSnapshot) -> String? {
        guard let v = s.volRatio, v > 0 else { return nil }
        return String(format: "vol %.2fx", v)
    }

    private func flowLabel(_ s: MarketSnapshot) -> String {
        guard let skew = s.flowSkew else { return "no tape" }
        let pct = Int((abs(skew) * 100).rounded())
        if pct <= 3 { return "balanced" }
        return skew > 0 ? "\(pct)% to UP" : "\(pct)% to DOWN"
    }

    private func explanation(_ s: MarketSnapshot) -> String {
        if s.flowSkew == nil {
            return "No trades in the last 30s, so flow is unknown. Absence of "
                + "tape is not balanced flow."
        }
        return "Bar is resting size within 2c of each touch; needle is 30s taker "
            + "flow across the pair. Neither gates a decision: the depth effect "
            + "was not stable across sample halves and the flow effect, though "
            + "sign-stable, was not significant. Shown to be checked, not trusted."
    }
}
