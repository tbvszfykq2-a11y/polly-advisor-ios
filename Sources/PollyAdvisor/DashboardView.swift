import SwiftUI
import UIKit

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSetup = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Markets", systemImage: "chart.bar.xaxis") }

            SignalsView()
                .tabItem { Label("Signals", systemImage: "bolt.horizontal.fill") }

            EdgeView()
                .tabItem { Label("Edge", systemImage: "checkmark.seal") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .onAppear {
            if model.needsSetup {
                showSetup = true
            } else {
                model.start()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.isConfigured {
                model.start()
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupSheet()
        }
    }
}

struct SetupSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsForm(onSaved: {
                dismiss()
            })
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.needsSetup)
    }
}

// MARK: - Brand

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.accent.opacity(0.9), Palette.up.opacity(0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("P")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.bg)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("POLLY ADVISOR")
                    .font(.label(12.5, .bold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.text)
                Text("crypto up/down · advisory")
                    .font(.mono(8.5))
                    .tracking(0.3)
                    .foregroundStyle(Palette.faint)
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    header
                    StatusStrip()
                    pinnedBest
                    intervalBoard
                    confidenceLegend
                    footerNote
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 26)
                // One animation for the whole board so rows slide when the
                // ranking changes instead of teleporting.
                .animation(Motion.board, value: model.windows.map(\.id))
            }
            .background(Palette.bg.ignoresSafeArea())
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { slug in
                if let window = model.windows.first(where: { $0.id == slug }) {
                    WindowDetailView(window: window)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Wordmark()
            Spacer()
            StatusPill(state: model.conn)
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    /// The best trade never scrolls away from the top of the board.
    @ViewBuilder
    private var pinnedBest: some View {
        if let best = model.bestTrade {
            NavigationLink(value: best.id) {
                BestTradeCard(window: best)
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if model.conn == .live {
            Panel {
                EmptyPanel(
                    icon: "shield.lefthalf.filled",
                    title: "No trade worth taking",
                    message: "Every quoted side is priced at or above fair value net of the "
                        + "taker fee. Standing down is the correct position."
                )
            }
        }
    }

    /// One section per contract length, in fixed order so the layout is stable
    /// even when a length has no markets.
    private var intervalBoard: some View {
        VStack(spacing: 14) {
            ForEach(model.intervalMinutes, id: \.self) { minutes in
                intervalSection(minutes)
            }
        }
    }

    @ViewBuilder
    private func intervalSection(_ minutes: Int) -> some View {
        let rows = model.markets(minutes: minutes)

        VStack(spacing: 8) {
            SectionHeader(
                title: "\(minutes) min",
                detail: rows.isEmpty ? "none" : "\(rows.count) market\(rows.count == 1 ? "" : "s")"
            )

            if rows.isEmpty {
                Panel {
                    EmptyPanel(
                        icon: minutes == 10 ? "slash.circle" : "antenna.radiowaves.left.and.right.slash",
                        title: minutes == 10 ? "Not offered upstream" : "No markets right now",
                        message: minutes == 10
                            ? "Polymarket lists crypto Up/Down at 5 and 15 minutes only, so this "
                                + "section stays empty by design rather than hiding a gap."
                            : (model.conn == .live
                                ? "The engine has not discovered markets for the configured assets."
                                : "Waiting for the first successful poll.")
                    )
                }
            } else {
                ForEach(rows) { window in
                    NavigationLink(value: window.id) {
                        WindowCard(window: window)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
    }

    /// Measured hit rate for the model's own confidence, from 289,563 snapshots.
    /// Shown because "how often is this right" is the question a reader actually
    /// has, and it is monotone: selectivity buys accuracy, not profit.
    private var confidenceLegend: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("HIT RATE AT THIS CONFIDENCE")
                .font(.mono(9))
                .foregroundStyle(Palette.faint)
            HStack(spacing: 0) {
                legendCell("≥90%", "90.8%", "all windows")
                legendCell("≥95%", "95.5%", "all windows")
                legendCell("≥90% @30s", "98.5%", "last 30s")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.stroke))
    }

    private func legendCell(_ key: String, _ value: String, _ note: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.mono(13).weight(.semibold))
                .foregroundStyle(Palette.up)
                .contentTransition(.numericText())
            Text(key)
                .font(.mono(9))
                .foregroundStyle(Palette.dim)
            Text(note)
                .font(.mono(8))
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private var footerNote: some View {
        VStack(spacing: 6) {
            // The measured result, stated plainly. The model is useful as a
            // probability; it is not a licence to assume profit.
            Text("Probabilities are calibrated on 1,291 resolved windows "
                 + "(Brier 0.16, 76% directional). Measured across the same sample, "
                 + "no entry rule cleared the ~3.5¢ round-trip fee — treat a signal "
                 + "as a fair-value read, not a guaranteed edge.")
                .font(.mono(9))
                .foregroundStyle(Palette.faint.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.lastError ?? "Advisory only — you place every order yourself.")
                .font(.mono(9.5))
                .foregroundStyle(model.lastError == nil ? Palette.faint : Palette.down.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let updated = model.lastUpdate {
                Text("updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.mono(9))
                    .foregroundStyle(Palette.faint.opacity(0.7))
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
    }
}

// MARK: - Status strip

struct StatusStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let s = model.state
        Panel(padding: 12) {
            HStack(spacing: 0) {
                Metric(label: "Ticks", value: Fmt.compact(s?.ticks), size: 13)
                divider
                Metric(label: "Uptime", value: uptime(s?.uptimeS), size: 13)
                divider
                Metric(label: "Books", value: "\(s?.book?.tokens ?? 0)", size: 13)
                divider
                Metric(label: "TWAP lag", value: Fmt.ago(worstTwapAge(s)), size: 13)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 0.75, height: 24)
            .padding(.horizontal, 8)
    }

    private func uptime(_ s: Double?) -> String {
        guard let s else { return "—" }
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func worstTwapAge(_ s: StateResponse?) -> Double? {
        let ages = (s?.twap ?? [:]).compactMap { $0.value.ageS }
        return ages.max()
    }
}

// MARK: - Window card

struct WindowCard: View {
    let window: MarketWindow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let s = window.snapshot
        let asset = window.asset ?? s?.asset
        let beat = s?.beat
        let spot = s?.spot
        let delta = s?.deltaBps
        let fair = s?.pUp
        let ask = s?.upAsk
        let points = model.points(for: window).map(\.spot)
        let bestSide = s?.bestSide
        let bestEdge = s?.bestEdge

        Panel(padding: 13, highlight: (bestEdge ?? 0) > 0) {
            VStack(spacing: 10) {
                // Identity + countdown
                HStack(spacing: 10) {
                    AssetMark(asset: asset, size: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(AssetStyle.ticker(asset))
                                .font(.label(13.5, .semibold))
                                .foregroundStyle(Palette.text)
                            IntervalChip(minutes: window.intervalMinutes)
                            if window.preopen == true || s?.preopen == true {
                                SideChip(text: "PRE", tint: Palette.faint)
                            }
                        }
                        Text(beatSource(s))
                            .font(.mono(9))
                            .foregroundStyle(Palette.faint)
                    }

                    Spacer(minLength: 4)

                    LiveCountdown(
                        closesAt: window.closesAt,
                        fallback: s?.tRemaining ?? window.tRemaining ?? 0,
                        total: window.intervalSeconds
                    )
                }

                // Prices
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        MicroLabel(text: "To beat")
                        SmoothValue(text: Fmt.price(beat), font: .mono(13, .medium))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        MicroLabel(text: "Spot")
                        HStack(spacing: 5) {
                            SmoothValue(text: Fmt.price(spot), font: .mono(13, .medium))
                            if let d = delta {
                                SmoothValue(
                                    text: Fmt.signedBps(d),
                                    font: .mono(9.5, .semibold),
                                    tint: d >= 0 ? Palette.up : Palette.down
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if points.count >= 2 {
                    Sparkline(
                        values: points,
                        baseline: beat,
                        tint: (delta ?? 0) >= 0 ? Palette.up : Palette.down,
                        lineWidth: 1.5
                    )
                    .frame(height: 26)
                }

                // Fair value vs market
                VStack(spacing: 5) {
                    ProbBar(fair: fair ?? 0.5, market: ask)
                    HStack {
                        SmoothValue(text: "FAIR \(Fmt.pct(fair))",
                                    font: .mono(9), tint: Palette.dim)
                        Spacer()
                        SmoothValue(text: "MKT \(Fmt.cents(ask))",
                                    font: .mono(9), tint: Palette.warn.opacity(0.95))
                    }
                }

                // Verdict
                HStack(spacing: 7) {
                    if let side = bestSide {
                        SideChip(text: side, tint: side == "UP" ? Palette.up : Palette.down, filled: true)
                        EdgeBadge(edge: bestEdge)
                    } else {
                        SideChip(text: "NO EDGE", tint: Palette.faint)
                    }
                    Spacer(minLength: 4)
                    if let m = s?.momentumBps {
                        Text("mom \(Fmt.signedBps(m))")
                            .font(.mono(9))
                            .foregroundStyle(m >= 0 ? Palette.up.opacity(0.8) : Palette.down.opacity(0.8))
                    }
                }
            }
        }
    }

    private func beatSource(_ s: MarketSnapshot?) -> String {
        let src = (s?.beatSrc ?? "—").uppercased()
        let feed = (s?.feed ?? "—").lowercased()
        return "\(src) · \(feed)"
    }
}

// MARK: - Detail

struct WindowDetailView: View {
    let window: MarketWindow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let s = window.snapshot
        let points = model.points(for: window)
        let verdict = Verdict(s: s)
        let related = model.advice.first { $0.slug == window.slug }

        ScrollView {
            VStack(spacing: 12) {
                headerCard(verdict)

                if points.count >= 2 {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Path since open", detail: "\(points.count) samples")
                            Sparkline(
                                values: points.map(\.spot),
                                baseline: s?.beat,
                                tint: verdict.tint,
                                lineWidth: 2
                            )
                            .frame(height: 92)
                            HStack {
                                Text("beat \(Fmt.price(s?.beat))")
                                    .font(.mono(9))
                                    .foregroundStyle(Palette.faint)
                                Spacer()
                                Text("last \(Fmt.price(points.last?.spot))")
                                    .font(.mono(9))
                                    .foregroundStyle(Palette.dim)
                            }
                        }
                    }
                }

                mathCard(s, verdict: verdict)
                feedCard(s)

                if let adv = related {
                    adviceCard(adv)
                }

                actionsCard(window, s)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("\(AssetStyle.ticker(window.asset ?? s?.asset)) · \(window.intervalMinutes)m")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func headerCard(_ v: Verdict) -> some View {
        Panel(highlight: v.isActionable) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    AssetMark(asset: window.asset, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(v.headline)
                            .font(.label(17, .bold))
                            .foregroundStyle(v.tint)
                        Text(v.subline)
                            .font(.mono(9.5))
                            .foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    LiveCountdown(
                        closesAt: window.closesAt,
                        fallback: window.snapshot?.tRemaining ?? window.tRemaining ?? 0,
                        total: window.intervalSeconds
                    )
                }

                Rule()

                HStack(spacing: 0) {
                    Metric(label: "Fair", value: Fmt.pct(window.snapshot?.pUp), size: 15)
                    Metric(label: "Ask", value: Fmt.cents(window.snapshot?.upAsk), size: 15, tint: Palette.warn)
                    Metric(label: "Edge", value: Fmt.signedCents(window.snapshot?.bestEdge),
                           size: 15, tint: v.tint)
                }
            }
        }
    }

    private func mathCard(_ s: MarketSnapshot?, verdict: Verdict) -> some View {
        let side = verdict.side
        let ask = side == "DOWN" ? s?.downAsk : s?.upAsk
        let fair = side == "DOWN" ? (s?.pUp.map { 1 - $0 }) : s?.pUp
        let fee = MarketSnapshot.fee(price: ask)
        let breakeven = (ask ?? 0) + (fee ?? 0)
        let roi = (fair ?? 0) > 0 ? (verdict.edge / max(ask ?? 1, 0.0001)) : 0

        return Panel {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: "Edge maths", detail: side ?? "—")
                Rule().padding(.vertical, 6)

                KeyRow(key: "Model probability", value: Fmt.pct(fair, digits: 1))
                KeyRow(key: "Market ask", value: Fmt.cents(ask), tint: Palette.warn)
                KeyRow(key: "Taker fee (0.07·p·(1−p))", value: Fmt.cents(fee), tint: Palette.dim)
                KeyRow(key: "Breakeven price", value: Fmt.cents(breakeven), tint: Palette.dim)
                Rule().padding(.vertical, 6)
                KeyRow(key: "Net edge per share", value: Fmt.signedCents(verdict.edge), tint: verdict.tint)
                KeyRow(key: "Return on stake", value: Fmt.signedPct(roi), tint: verdict.tint)
                KeyRow(key: "Exit target (bid ≥)", value: Fmt.cents(fair), tint: Palette.up)
                KeyRow(key: "Model sigma", value: s?.sigma.map { String(format: "%.2f", $0) } ?? "—",
                       tint: Palette.dim)
            }
        }
    }

    private func feedCard(_ s: MarketSnapshot?) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: "Settlement & feed", detail: (s?.feed ?? "—").uppercased())
                Rule().padding(.vertical, 6)

                KeyRow(key: "Beat source", value: (s?.beatSrc ?? "—").uppercased())
                KeyRow(key: "TWAP-60", value: Fmt.price(s?.twap60))
                KeyRow(key: "TWAP age", value: Fmt.ago(s?.twapAgeS),
                       tint: (s?.twapAgeS ?? 0) > 8 ? Palette.warn : Palette.up)
                KeyRow(key: "Spot", value: Fmt.price(s?.spot))
                KeyRow(key: "Momentum", value: Fmt.signedBps(s?.momentumBps),
                       tint: (s?.momentumBps ?? 0) >= 0 ? Palette.up : Palette.down)
                KeyRow(key: "Book", value: bookLine(s))
            }
        }
    }

    private func bookLine(_ s: MarketSnapshot?) -> String {
        "up \(Fmt.cents(s?.upBid))/\(Fmt.cents(s?.upAsk)) · dn \(Fmt.cents(s?.downBid))/\(Fmt.cents(s?.downAsk))"
    }

    private func adviceCard(_ a: Advice) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    SideChip(text: (a.kind ?? "SIGNAL").uppercased(), tint: a.tint)
                    if let side = a.side { SideChip(text: side, tint: sideColor(side)) }
                    Spacer()
                    if let conf = a.conf {
                        Text(conf.uppercased())
                            .font(.mono(9, .bold))
                            .foregroundStyle(Palette.dim)
                    }
                }
                if let reason = a.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.label(11.5))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rule()
                HStack(spacing: 0) {
                    Metric(label: "Price", value: Fmt.cents(a.price), size: 13)
                    Metric(label: "Edge", value: Fmt.signedCents(a.edge), size: 13, tint: Palette.up)
                    Metric(label: "Size", value: a.sizeShares.map { "\($0)" } ?? "—", size: 13)
                    Metric(label: "Left", value: Fmt.clock(a.tRemaining), size: 13)
                }
            }
        }
    }

    private func sideColor(_ side: String) -> Color {
        side.uppercased() == "UP" ? Palette.up : Palette.down
    }

    private func actionsCard(_ w: MarketWindow, _ s: MarketSnapshot?) -> some View {
        Panel {
            VStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = summaryText(w, s)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("Copy trade sheet", systemImage: "doc.on.doc")
                        .font(.label(12.5, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .foregroundStyle(Palette.text)

                if let slug = w.slug,
                   let url = URL(string: "https://polymarket.com/event/\(slug)") {
                    Link(destination: url) {
                        Label("Open on Polymarket", systemImage: "arrow.up.right.square")
                            .font(.label(12.5, .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Palette.accent.opacity(0.14))
                            )
                    }
                    .foregroundStyle(Palette.accent)
                }
            }
        }
    }

    private func summaryText(_ w: MarketWindow, _ s: MarketSnapshot?) -> String {
        let v = Verdict(s: s)
        let ticker = AssetStyle.ticker(w.asset ?? s?.asset)
        return """
        POLLY ADVISOR — \(ticker) \(w.intervalMinutes)m
        slug: \(w.slug ?? "—")
        verdict: \(v.headline)
        fair: \(Fmt.pct(s?.pUp))  ask: \(Fmt.cents(s?.upAsk))
        edge: \(Fmt.signedCents(v.edge))
        beat: \(Fmt.price(s?.beat))  spot: \(Fmt.price(s?.spot))
        exit target: bid >= \(Fmt.cents(v.side == "DOWN" ? s?.pUp.map { 1 - $0 } : s?.pUp))
        time left: \(Fmt.clock(s?.tRemaining))
        """
    }
}

// MARK: - Verdict

struct Verdict {
    let side: String?
    let edge: Double
    let tint: Color
    let headline: String
    let subline: String

    var isActionable: Bool { side != nil && edge > 0 }

    init(s: MarketSnapshot?) {
        let up = s?.edgeUp ?? 0
        let down = s?.edgeDown ?? 0
        let best = max(up, down)
        let picked: String? = best > 0 ? (up >= down ? "UP" : "DOWN") : nil

        side = picked
        edge = best
        tint = picked == nil ? Palette.dim : (picked == "UP" ? Palette.up : Palette.down)

        if let picked {
            headline = "BUY \(picked)"
            let fair = picked == "UP" ? s?.pUp : s?.pUp.map { 1 - $0 }
            let ask = picked == "UP" ? s?.upAsk : s?.downAsk
            subline = "Fair \(Fmt.pct(fair)) vs ask \(Fmt.cents(ask)) — clears the taker fee."
        } else {
            headline = "NO EDGE"
            subline = "Both sides are priced at or above fair value net of fees."
        }
    }
}
