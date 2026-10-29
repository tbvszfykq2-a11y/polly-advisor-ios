import SwiftUI

// MARK: - Motion

/// One place for the app's motion vocabulary so nothing animates at a speed
/// that fights something else on screen.
enum Motion {
    /// Numbers and bars: fast enough to feel live, slow enough to read.
    static let value = Animation.easeInOut(duration: 0.45)
    /// Paths and fills that change shape.
    static let shape = Animation.easeInOut(duration: 0.65)
    /// List membership and ordering.
    static let board = Animation.easeInOut(duration: 0.38)
    /// Countdown tick — linear so the ring never looks like it stutters.
    static let tick = Animation.linear(duration: 0.9)
}

// MARK: - Smooth value

/// A number that morphs between readings instead of snapping.
///
/// The board polls every couple of seconds, so a plain `Text` flicks to the new
/// value and the whole table appears to jump. `numericText` slides only the
/// digits that changed, which keeps a scrolling board visually still.
struct SmoothValue: View {
    let text: String
    var font: Font = .mono(13, .medium)
    var tint: Color = Palette.text
    var animate: Bool = true

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(tint)
            .contentTransition(.numericText())
            .animation(animate ? Motion.value : nil, value: text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Live countdown

/// Counts down from the window's real close time on a 1 s timeline.
///
/// Deriving `remaining` from `closesAt` rather than from the last polled
/// `t_remaining` means the ring advances every second and never lurches by two
/// or three seconds when a poll lands.
struct LiveCountdown: View {
    let closesAt: Date?
    let fallback: Double
    let total: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining: Double = {
                guard let closesAt else { return fallback }
                return max(0, closesAt.timeIntervalSince(context.date))
            }()
            CountdownRing(remaining: remaining, total: total)
        }
    }
}

// MARK: - Progress with motion

/// Thin progress fill that eases to its new width.
struct SmoothBar: View {
    let fraction: Double
    var tint: Color = Palette.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let f = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.055))
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, geo.size.width * f))
                    .animation(Motion.value, value: f)
            }
        }
        .frame(height: height)
    }
}
