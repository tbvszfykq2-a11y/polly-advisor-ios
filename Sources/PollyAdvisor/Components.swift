import SwiftUI

// MARK: - Asset identity

enum AssetStyle {
    static func color(_ asset: String?) -> Color {
        switch (asset ?? "").lowercased() {
        case "btc":  return Color(hex: 0xF0A03C)
        case "eth":  return Color(hex: 0x8E9CF5)
        case "sol":  return Color(hex: 0xA98BF5)
        case "xrp":  return Color(hex: 0x63CBBE)
        case "doge": return Color(hex: 0xC9B26B)
        default:     return Palette.accent
        }
    }

    static func ticker(_ asset: String?) -> String {
        let a = (asset ?? "?").uppercased()
        return a.isEmpty ? "?" : a
    }
}

struct AssetMark: View {
    let asset: String?
    var size: CGFloat = 30

    var body: some View {
        let tint = AssetStyle.color(asset)
        Text(AssetStyle.ticker(asset))
            .font(.mono(size * 0.34, .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.11)))
            .overlay(Circle().strokeBorder(tint.opacity(0.28), lineWidth: 0.75))
    }
}

// MARK: - Countdown

struct CountdownRing: View {
    let remaining: Double
    let total: Double

    var body: some View {
        let frac = total > 0 ? min(1, max(0, remaining / total)) : 0
        let tint = Self.tint(remaining: remaining)
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: 3)
            Circle()
                .trim(from: 0, to: frac)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(Fmt.clock(remaining))
                .font(.mono(10.5, .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 44, height: 44)
    }

    static func tint(remaining: Double) -> Color {
        if remaining <= 45  { return Palette.down }
        if remaining <= 120 { return Palette.warn }
        return Palette.up
    }
}

// MARK: - Sparkline

/// Price path since the window opened, with the strike (price to beat) as a
/// dashed reference. Scale always includes the baseline so the crossing is
/// readable at a glance.
struct Sparkline: View {
    let values: [Double]
    var baseline: Double? = nil
    var tint: Color = Palette.accent
    var lineWidth: CGFloat = 1.6

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let all = values + (baseline.map { [$0] } ?? [])
            let lo = all.min() ?? 0
            let hi = all.max() ?? 1
            let span = max(hi - lo, max(abs(hi) * 0.0002, 1e-9))
            let plot = Plot(values: values, lo: lo, span: span, size: size)

            ZStack {
                if let b = baseline, b.isFinite {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: plot.y(b)))
                        p.addLine(to: CGPoint(x: size.width, y: plot.y(b)))
                    }
                    .stroke(Palette.faint.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                Path { p in
                    let pts = plot.points
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() {
                        p.addLine(to: pt)
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth,
                                                 lineCap: .round, lineJoin: .round))

                if let last = values.last, values.count > 1 {
                    Circle()
                        .fill(tint)
                        .frame(width: 4.5, height: 4.5)
                        .position(x: plot.x(values.count - 1), y: plot.y(last))
                        .shadow(color: tint.opacity(0.9), radius: 3.5)
                }
            }
        }
    }

    /// Pure geometry helper — kept outside the ViewBuilder so the closure stays
    /// declaration-free.
    private struct Plot {
        let values: [Double]
        let lo: Double
        let span: Double
        let size: CGSize

        func y(_ v: Double) -> CGFloat {
            size.height - CGFloat((v - lo) / span) * size.height
        }

        func x(_ i: Int) -> CGFloat {
            values.count <= 1
                ? size.width / 2
                : size.width * CGFloat(i) / CGFloat(values.count - 1)
        }

        var points: [CGPoint] {
            values.enumerated().map { i, v in
                CGPoint(x: x(i), y: y(v))
            }
        }
    }
}

// MARK: - Probability bar

/// Fair value as a filled bar, with the 50% line and the market's ask drawn as
/// vertical markers. The gap between the bar end and the amber marker is the
/// edge — the entire thesis of the app in one glyph.
struct ProbBar: View {
    let fair: Double
    let market: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let f = min(1, max(0, fair))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.055))

                Capsule()
                    .fill(LinearGradient(
                        colors: [Palette.accent.opacity(0.8), Palette.up.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, w * f))

                Rectangle()
                    .fill(Palette.faint.opacity(0.55))
                    .frame(width: 1)
                    .offset(x: w * 0.5)

                if let m = market, m.isFinite {
                    Rectangle()
                        .fill(Palette.warn)
                        .frame(width: 2)
                        .offset(x: min(w - 2, max(0, w * m)))
                        .shadow(color: Palette.warn.opacity(0.85), radius: 3)
                }
            }
        }
        .frame(height: 7)
    }
}

// MARK: - Chips & labels

struct EdgeBadge: View {
    let edge: Double?
    var compact: Bool = false

    var body: some View {
        let e = edge ?? 0
        let tint = e > 0.0005 ? Palette.up : (e < -0.0005 ? Palette.down : Palette.faint)
        Text(abs(e) < 0.0005 ? "FLAT" : Fmt.signedCents(e))
            .font(.mono(compact ? 10 : 11, .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 0.75)
            )
    }
}

struct IntervalChip: View {
    let minutes: Int
    var body: some View {
        Text("\(minutes)M")
            .font(.mono(9, .bold))
            .tracking(0.5)
            .foregroundStyle(Palette.dim)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MicroLabel(text: title, tint: Palette.dim)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.mono(9.5))
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// Small key/value row used in detail tables.
struct KeyRow: View {
    let key: String
    let value: String
    var tint: Color = Palette.text
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.label(11.5))
                .foregroundStyle(Palette.dim)
            if let note {
                Text(note)
                    .font(.mono(9))
                    .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 6)
            Text(value)
                .font(.mono(12, .medium))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
    }
}

/// Empty-state panel with an icon, used for "no actionable edges".
struct EmptyPanel: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.faint)
            Text(title)
                .font(.label(12.5, .semibold))
                .foregroundStyle(Palette.dim)
            Text(message)
                .font(.label(11))
                .foregroundStyle(Palette.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
    }
}
