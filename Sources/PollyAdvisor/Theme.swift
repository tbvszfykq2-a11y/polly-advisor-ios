import SwiftUI

// MARK: - Palette

/// Dark, low-chroma instrument panel. Colour is reserved for meaning:
/// green = edge / up, rose = down / overpriced, amber = attention.
enum Palette {
    static let bg        = Color(hex: 0x070A0F)
    static let surface   = Color(hex: 0x0D131B)
    static let surfaceHi = Color(hex: 0x131C26)
    static let stroke    = Color.white.opacity(0.07)
    static let strokeHi  = Color.white.opacity(0.13)

    static let text      = Color(hex: 0xE7EEF6)
    static let dim       = Color(hex: 0x8B9AAB)
    static let faint     = Color(hex: 0x55636F)

    static let up        = Color(hex: 0x2EE6A8)
    static let down      = Color(hex: 0xFF5E7A)
    static let warn      = Color(hex: 0xFFC24B)
    static let accent    = Color(hex: 0x5B9DFF)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Type

extension Font {
    /// Monospaced digits for every number — prices must align column-wise.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func label(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Formatting

enum Fmt {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func price(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        grouped.minimumFractionDigits = 2
        grouped.maximumFractionDigits = 2
        return grouped.string(from: NSNumber(value: v)) ?? "—"
    }

    /// Contract prices are 0…1; render as cents for legibility.
    static func cents(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%.1f¢", v * 100)
    }

    static func signedCents(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%@%.1f¢", v >= 0 ? "+" : "−", abs(v) * 100)
    }

    static func pct(_ v: Double?, digits: Int = 1) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%.\(digits)f%%", v * 100)
    }

    static func signedPct(_ v: Double?, digits: Int = 1) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%@%.\(digits)f%%", v >= 0 ? "+" : "−", abs(v) * 100)
    }

    static func clock(_ s: Double?) -> String {
        guard let s, s.isFinite else { return "—:—" }
        let t = max(0, Int(s.rounded()))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    static func signedBps(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%@%.1fbp", v >= 0 ? "+" : "−", abs(v))
    }

    static func ago(_ s: Double?) -> String {
        guard let s, s.isFinite else { return "—" }
        if s < 1 { return String(format: "%.0fms", s * 1000) }
        return String(format: "%.1fs", s)
    }

    static func compact(_ v: Int?) -> String {
        guard let v else { return "—" }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fk", Double(v) / 1_000) }
        return "\(v)"
    }

    static func bytes(_ v: Int64?) -> String {
        guard let v else { return "—" }
        let mb = Double(v) / 1_048_576
        return mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.1f MB", mb)
    }
}

// MARK: - Building blocks

/// Standard panel: hairline stroke, faint vertical gradient, generous padding.
struct Panel<Content: View>: View {
    var padding: CGFloat = 14
    var highlight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: highlight
                                ? [Palette.surfaceHi, Palette.surface]
                                : [Palette.surface, Palette.bg],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(highlight ? Palette.strokeHi : Palette.stroke, lineWidth: 0.75)
            )
    }
}

/// Uppercase, letter-spaced micro-label used above every metric.
struct MicroLabel: View {
    let text: String
    var tint: Color = Palette.faint
    var body: some View {
        Text(text.uppercased())
            .font(.label(9.5, .semibold))
            .tracking(1.1)
            .foregroundStyle(tint)
    }
}

/// A single number with its caption, monospaced and column-stable.
struct Metric: View {
    let label: String
    let value: String
    var tint: Color = Palette.text
    var size: CGFloat = 15
    var mono: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            MicroLabel(text: label)
            Text(value)
                .font(mono ? .mono(size, .medium) : .label(size, .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hairline rule that reads as structure rather than decoration.
struct Rule: View {
    var opacity: Double = 0.07
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(opacity))
            .frame(height: 0.75)
    }
}

// MARK: - Status

enum ConnState: Equatable {
    case idle, connecting, live, stale, failed(String)

    var label: String {
        switch self {
        case .idle:            return "IDLE"
        case .connecting:      return "SYNC"
        case .live:            return "LIVE"
        case .stale:           return "STALE"
        case .failed:          return "OFFLINE"
        }
    }

    var tint: Color {
        switch self {
        case .idle:            return Palette.faint
        case .connecting:      return Palette.accent
        case .live:            return Palette.up
        case .stale:           return Palette.warn
        case .failed:          return Palette.down
        }
    }
}

struct StatusPill: View {
    let state: ConnState
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.tint)
                .frame(width: 5.5, height: 5.5)
                .shadow(color: state.tint.opacity(0.8), radius: 3)
            Text(state.label)
                .font(.mono(9.5, .bold))
                .tracking(0.8)
                .foregroundStyle(state.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(state.tint.opacity(0.12))
        )
        .overlay(Capsule().strokeBorder(state.tint.opacity(0.28), lineWidth: 0.75))
    }
}

/// Direction-coded chip: UP / DOWN / NO EDGE.
struct SideChip: View {
    let text: String
    let tint: Color
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.mono(10, .bold))
            .tracking(0.6)
            .foregroundStyle(filled ? Palette.bg : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(filled ? tint : tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(tint.opacity(filled ? 0 : 0.3), lineWidth: 0.75)
            )
    }
}
