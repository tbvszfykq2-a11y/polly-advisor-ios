import SwiftUI

/// Coarse elapsed label for settled rows.
///
/// `Fmt.ago` is built for sub-second feed freshness and would render a window
/// that closed an hour ago as "3600.0s". Settlement is a minutes-and-hours
/// question, so this rounds to the unit that actually matters.
private func elapsedLabel(_ seconds: Double) -> String {
    let s = max(0, seconds)
    if s < 60 { return "\(Int(s))s ago" }
    if s < 3_600 { return "\(Int(s / 60))m ago" }
    if s < 86_400 { return "\(Int(s / 3_600))h ago" }
    return "\(Int(s / 86_400))d ago"
}

// MARK: - Review

/// The retrospective: markets that already settled, and what that taught the engine.
///
/// The board only ever shows markets you can still act on, so the record of what
/// happened would otherwise be invisible. This section holds it: every settled
/// window with the engine's last read, plus the measured lessons those
/// settlements produced and the change each one makes to the next prediction.
///
/// Nothing here is a slogan. Each lesson prints the sample size it was measured
/// on; a lesson without one would be an assertion dressed as a finding.
struct ReviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                ReviewBody()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(Palette.bg.ignoresSafeArea())
            .refreshable { await model.refreshReview() }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The content of the review, without its own navigation container so it can be
/// pushed from elsewhere without nesting two stacks.
struct ReviewBody: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        LazyVStack(spacing: 12) {
            if let review = model.review {
                influencePanel(review)
                countsPanel(review)
                lessonsPanel(review)
                recentPanel(review)
                modelPanel(review)
                slicesPanel(review)
                footer(review)
            } else if model.conn == .live {
                Panel {
                    EmptyPanel(
                        icon: "clock.arrow.circlepath",
                        title: "No settled windows loaded yet",
                        message: "The server grades windows after they close. Pull to refresh once the "
                            + "first one has settled."
                    )
                }
            } else {
                Panel {
                    EmptyPanel(
                        icon: "antenna.radiowaves.left.and.right.slash",
                        title: "Not connected",
                        message: "The review is read from the advisor server. Check the endpoint in "
                            + "Settings."
                    )
                }
            }
        }
    }

    // MARK: Influence

    /// The sentence that answers "what did the past teach the next call".
    private func influencePanel(_ review: ReviewResponse) -> some View {
        Panel(highlight: true) {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeader(
                    title: "How this shapes the next call",
                    detail: review.generatedAt.map { elapsedLabel(Date().timeIntervalSince($0)) }
                )
                Rule()

                Text(review.influence
                     ?? "Not enough settled windows yet to say what the next call should learn from.")
                    .font(.label(12))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("These are measurements taken on the server from settled windows, and the engine "
                     + "applies them to the next prediction. They are not restated here as confidence.")
                    .font(.mono(9))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Counts

    private func countsPanel(_ review: ReviewResponse) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "Recently settled",
                    detail: "\(review.recentList.count) listed · \(review.counts?.resolved ?? 0) graded"
                )
                Rule()
                HStack(spacing: 0) {
                    Metric(label: "Book called",
                           value: Fmt.pct(review.bookAccuracy),
                           size: 16, tint: Palette.up)
                    Metric(label: "Model called",
                           value: Fmt.pct(review.modelAccuracy),
                           size: 16, tint: Palette.down)
                    Metric(label: "Disagreed",
                           value: "\(review.counts?.disagreements ?? 0)",
                           size: 16, tint: Palette.warn)
                }
                Text("A share of the rows shown, not a long-run rate. The paired comparison over "
                     + "every graded row is in Model vs book below.")
                    .font(.mono(8.5))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Lessons

    private func lessonsPanel(_ review: ReviewResponse) -> some View {
        VStack(spacing: 8) {
            SectionHeader(
                title: "What the settled windows taught",
                detail: "\(review.lessonsList.count) measured"
            )
            ForEach(review.lessonsList) { lesson in
                LessonRow(lesson: lesson)
            }
        }
    }

    // MARK: Previous markets

    private func recentPanel(_ review: ReviewResponse) -> some View {
        VStack(spacing: 8) {
            SectionHeader(title: "Previous markets", detail: "newest first")
            if review.recentList.isEmpty {
                Panel {
                    EmptyPanel(
                        icon: "tray",
                        title: "Nothing settled yet",
                        message: "Each settled window appears here with the engine's last read, "
                            + "what the book said, and who was right."
                    )
                }
            } else {
                ForEach(review.recentList) { market in
                    SettledMarketRow(market: market)
                }
            }
        }
    }

    // MARK: Model vs book

    private func modelPanel(_ review: ReviewResponse) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeader(
                    title: "Model vs book",
                    detail: review.modelVsBook.map { "\($0.n ?? 0) rows" }
                )
                Rule()

                if let mb = review.modelVsBook, let m = mb.model, let b = mb.book {
                    HStack(spacing: 0) {
                        Metric(label: "Model Brier",
                               value: String(format: "%.3f", m.brier ?? 0),
                               size: 15, tint: Palette.down)
                        Metric(label: "Book Brier",
                               value: String(format: "%.3f", b.brier ?? 0),
                               size: 15, tint: Palette.up)
                        Metric(label: "Model called",
                               value: Fmt.pct(m.acc),
                               size: 15)
                    }

                    Text("Lower Brier is better. Both scores are on the same rows, so the gap is "
                         + "like-for-like rather than two separate runs.")
                        .font(.mono(8.5))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(mb.orderedGaps) { gap in
                        HStack(spacing: 8) {
                            Text(gap.id)
                                .font(.mono(8.5))
                                .foregroundStyle(Palette.faint)
                                .frame(width: 60, alignment: .leading)
                            SmoothBar(fraction: gap.stat.bookWinRate ?? 0,
                                      tint: Palette.up.opacity(0.55),
                                      height: 5)
                            Text(Fmt.pct(gap.stat.bookWinRate))
                                .font(.mono(9))
                                .foregroundStyle(Palette.dim)
                                .frame(width: 40, alignment: .trailing)
                            Text("n=\(Fmt.compact(gap.stat.n))")
                                .font(.mono(8.5))
                                .foregroundStyle(Palette.faint)
                                .frame(width: 58, alignment: .trailing)
                        }
                    }

                    Text("Rows are bucketed by how far the model and the book disagree. The bar is "
                         + "the share of those rows the book called correctly.")
                        .font(.mono(8.5))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No graded rows carry both probabilities yet, so there is nothing to compare.")
                        .font(.mono(9))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Realised result by market. The comparison is the point: one aggregate
    /// hides a five-fold spread between slices, and only the worst ones are
    /// separated from zero by more than two standard errors.
    private func slicesPanel(_ review: ReviewResponse) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeader(
                    title: "Realised result by market",
                    detail: review.slices?.overall.map { "\(Fmt.compact($0.n)) graded buys" }
                )
                Rule()

                if let s = review.slices, let overall = s.overall {
                    HStack(spacing: 0) {
                        Metric(label: "Aggregate",
                               value: overall.evLabel,
                               size: 15, tint: Palette.down)
                        Metric(label: "Hit rate",
                               value: Fmt.pct(overall.hitRate),
                               size: 15)
                        Metric(label: "±2 SE",
                               value: String(format: "%.2fc", 2 * (overall.seCents ?? 0)),
                               size: 15)
                    }

                    ForEach(s.orderedPairs) { row in
                        HStack(spacing: 8) {
                            Text(row.id.replacingOccurrences(of: "/", with: " · "))
                                .font(.mono(9))
                                .foregroundStyle(Palette.dim)
                                .frame(width: 76, alignment: .leading)
                            Text(row.cell.evLabel)
                                .font(.mono(10))
                                .monospacedDigit()
                                .foregroundStyle(row.cell.isDistinguishable ? Palette.down : Palette.faint)
                                .frame(width: 52, alignment: .trailing)
                            Text("±\(String(format: "%.2f", row.cell.seCents ?? 0))c")
                                .font(.mono(8.5))
                                .foregroundStyle(Palette.faint)
                                .frame(width: 46, alignment: .trailing)
                            Text("n=\(Fmt.compact(row.cell.n))")
                                .font(.mono(8.5))
                                .foregroundStyle(Palette.faint)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    Text("Per share, net of the taker fee. Every slice is negative over the "
                         + "recorded history, so this is a measure of how badly each market loses, "
                         + "not a ranking to trade. A slice whose estimate is within two standard "
                         + "errors of zero is drawn faint: it is indistinguishable from flat.")
                        .font(.mono(8.5))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No graded BUY advice yet, so there is no realised result to slice.")
                        .font(.mono(9))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Footer

    private func footer(_ review: ReviewResponse) -> some View {
        VStack(spacing: 5) {
            Text("Computed on the server from settled windows and cached for "
                 + "\(Int(review.ttlS ?? 60))s, so a pull to refresh can return the same "
                 + "timestamp. The board itself refreshes every \(String(format: "%.1f", model.pollSeconds))s.")
                .font(.mono(8.5))
                .foregroundStyle(Palette.faint.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let generated = review.generatedAt {
                Text("Measured \(generated.formatted(date: .omitted, time: .standard))")
                    .font(.mono(8.5))
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Lesson row

struct LessonRow: View {
    let lesson: ReviewLesson

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(lesson.title ?? lesson.id)
                        .font(.label(12.5, .semibold))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let n = lesson.n {
                        Text("n=\(Fmt.compact(n))")
                            .font(.mono(8.5))
                            .foregroundStyle(Palette.faint)
                    }
                }

                if let statement = lesson.statement {
                    Text(statement)
                        .font(.mono(10.5))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let implication = lesson.implication {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .padding(.top, 2)
                        Text(implication)
                            .font(.label(10.5))
                            .foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Settled market row

struct SettledMarketRow: View {
    let market: ReviewMarket

    private var outcomeTint: Color {
        if market.outcomeIsUp == true { return Palette.up }
        if market.outcomeIsUp == false { return Palette.down }
        return Palette.faint
    }

    private var readLine: String {
        guard let kind = market.kind?.uppercased(), !kind.isEmpty else { return "no advice" }
        if kind == "BUY", let side = market.side {
            return "BUY \(side.uppercased()) @ \(Fmt.cents(market.price))"
        }
        if kind == "SELL", let side = market.side {
            return "EXIT \(side.uppercased()) @ \(Fmt.cents(market.price))"
        }
        return kind
    }

    var body: some View {
        Panel {
            HStack(alignment: .top, spacing: 10) {
                AssetMark(asset: market.asset, size: 26)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(AssetStyle.ticker(market.asset))
                            .font(.label(12.5, .bold))
                            .foregroundStyle(Palette.text)
                        if let minutes = market.intervalMinutes {
                            IntervalChip(minutes: minutes)
                        }
                        Spacer(minLength: 4)
                        Text("SETTLED \((market.outcome ?? "—").uppercased())")
                            .font(.mono(8.5, .bold))
                            .tracking(0.4)
                            .foregroundStyle(outcomeTint)
                    }

                    HStack(spacing: 8) {
                        Text(readLine)
                            .font(.mono(9.5))
                            .foregroundStyle(Palette.dim)
                        Spacer(minLength: 4)
                        if let closed = market.closedAt {
                            Text(elapsedLabel(Date().timeIntervalSince(closed)))
                                .font(.mono(8.5))
                                .foregroundStyle(Palette.faint)
                        }
                    }

                    HStack(spacing: 10) {
                        estimator("Model", value: market.modelP, right: market.modelRight)
                        estimator("Book", value: market.pMarket, right: market.bookRight)
                        Spacer(minLength: 4)
                        if let pnl = market.pnlCents {
                            Text(String(format: "%+.1f¢", pnl))
                                .font(.mono(10, .medium))
                                .foregroundStyle(pnl >= 0 ? Palette.up : Palette.down)
                        } else if let hit = market.hit {
                            Text(hit ? "HIT" : "MISS")
                                .font(.mono(9, .bold))
                                .foregroundStyle(hit ? Palette.up : Palette.down)
                        }
                    }
                }
            }
        }
    }

    /// One estimator's call and whether it was right. The tick or cross is the
    /// whole point of this row: on this tape the book is right far more often,
    /// and that only shows when both are printed side by side.
    private func estimator(_ label: String, value: Double?, right: Bool?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.mono(8.5))
                .foregroundStyle(Palette.faint)
            Text(Fmt.pct(value))
                .font(.mono(9.5, .medium))
                .foregroundStyle(Palette.dim)
            if let right {
                Image(systemName: right ? "checkmark" : "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(right ? Palette.up : Palette.down)
            }
        }
    }
}
