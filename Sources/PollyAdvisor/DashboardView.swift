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

            ReviewView()
                .tabItem { Label("Review", systemImage: "clock.arrow.circlepath") }

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
            switch phase {
            case .active:
                // start() always refreshes immediately, so the board is live on
                // the first frame instead of showing whatever was on screen when
                // iOS suspended the process.
                if model.isConfigured { model.start() }
            case .background:
                // Stop the timer when the app is not visible: a backgrounded
                // poll loop is either suspended mid-request (leaving the board
                // stale) or spends battery on data nobody is reading.
                model.stop()
            default:
                break
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
                    pressureStrip
                    nextUp
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

    /// Book pressure for the window the board is already focused on, so the
    /// numbers sit next to the verdict they are context for.
    @ViewBuilder
    private var pressureStrip: some View {
        if let focus = model.bestTrade ?? model.activeWindows.first {
            BookPressureStrip(window: focus)
        }
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
                if model.activeWindows.isEmpty {
                    EmptyPanel(
                        icon: "hourglass",
                        title: "No market is open right now",
                        message: "The next window is listed below with its prediction. "
                            + "Nothing can be entered until that window opens."
                    )
                } else {
                    EmptyPanel(
                        icon: "shield.lefthalf.filled",
                        title: "No trade worth taking",
                        message: "Every quoted side is priced at or above the model's probability "
                            + "net of the taker fee. Standing down is the correct position."
                    )
                }
            }
        }
    }

    /// The prediction for the window that has not opened yet.
    ///
    /// Its own section, not a row in the live board. A pre-open market has a
    /// forecast and no entry, and the earlier board rendered those two states
    /// identically — which is how a reader ended up looking at a countdown for a
    /// market they could not trade.
    @ViewBuilder
    private var nextUp: some View {
        let upcoming = model.nextWindows
        if !upcoming.isEmpty {
            VStack(spacing: 8) {
                SectionHeader(
                    title: "Next market",
                    detail: upcoming.count == 1
                        ? "opens in \(Fmt.clock(upcoming[0].secondsToOpen))"
                        : "\(upcoming.count) queued"
                )
                ForEach(upcoming) { window in
                    NextMarketCard(window: window)
                }
            }
            .transition(.opacity)
        }
    }

    /// One section per contract length, in fixed order so the layout is stable
    /// even when a length has no markets.
    ///
    /// Only open windows render here. The server already filters closed ones out
    /// of `/api/state`, and `model.markets(minutes:)` re-checks the clock, so a
    /// window cannot linger on the board after its close.
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
                detail: rows.isEmpty ? "none open" : "\(rows.count) open"
            )

            if rows.isEmpty {
                Panel {
                    EmptyPanel(
                        icon: minutes == 10 ? "slash.circle" : "antenna.radiowaves.left.and.right.slash",
                        title: minutes == 10 ? "Not offered upstream" : "No open market",
                        message: minutes == 10
                            ? "Polymarket lists crypto Up/Down at 5 and 15 minutes only, so this "
                                + "section stays empty by design rather than hiding a gap."
                            : (model.conn == .live
                                ? "No window of this length is open right now. The next one "
                                    + "appears above as soon as it is discovered."
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
            // The measured numbers, stated plainly. The model loses to the book, so
            // it is shown as a divergence flag rather than a fair-value estimate.
            Text("Measured on 1,822 held-out windows: this model scores Brier 0.234 "
                 + "(58.7% directional), the book's own mid scores 0.137 (78.8%). "
                 + "Taker buying measured −1.8¢/share over 12,816 resolved rows. "
                 + "Read the model as a divergence flag, not as fair value.")
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
        let modelP = s?.pUp
        let ask = s?.upAsk
        let points = model.points(for: window).map(\.spot)
        // The row's verdict mirrors the server's call when there is one. Falling
        // back to `bestSide`/`bestEdge` alone marked rows as promising that the
        // engine had answered WATCH, which is the contradiction this gate exists
        // to remove. `isTradeable` is the single source of truth.
        let bestSide = ((s?.serverValidatedTrade == true ? s?.advice?.side : nil)
                        ?? s?.bestSide)
        let bestEdge = ((s?.serverValidatedTrade == true ? s?.advice?.edge : nil)
                        ?? s?.bestEdge)
        let tradeable = s?.isTradeable == true

        Panel(padding: 13, highlight: tradeable) {
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

                // Model probability vs the book's own mid vs the ask. The book's
                // mid is the calibrated fair value; the model is shown beside it so
                // the gap is visible rather than hidden behind the word "fair".
                VStack(spacing: 5) {
                    ProbBar(fair: modelP ?? 0.5, market: ask)
                    HStack(spacing: 6) {
                        SmoothValue(text: "MODEL \(Fmt.pct(modelP))",
                                    font: .mono(9), tint: Palette.dim)
                        if s?.pMarket != nil {
                            SmoothValue(text: "BOOK \(Fmt.pct(s?.bookUp))",
                                        font: .mono(9), tint: Palette.up.opacity(0.95))
                        }
                        Spacer(minLength: 4)
                        SmoothValue(text: "ASK \(Fmt.cents(ask))",
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

    /// True once the server has stopped serving this window.
    ///
    /// The detail view is pushed with a copy of the window, so without this
    /// check it would keep showing stale numbers with a frozen countdown after
    /// the market closed — the same defect the board had, one screen deeper.
    private var isClosed: Bool {
        !model.windows.contains { $0.id == window.id }
    }

    var body: some View {
        let s = window.snapshot
        let points = model.points(for: window)
        let verdict = Verdict(s: s)
        let related = model.advice.first { $0.slug == window.slug }

        ScrollView {
            VStack(spacing: 12) {
                if isClosed {
                    Panel {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(Palette.faint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("This market has closed")
                                    .font(.label(12, .semibold))
                                    .foregroundStyle(Palette.dim)
                                Text("The numbers below are the last read before the close, kept so "
                                     + "you can compare them with the result. It is no longer on the "
                                     + "board, and the outcome is in Review.")
                                    .font(.mono(9))
                                    .foregroundStyle(Palette.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

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
                    // "Model", not "Fair": the edge beside it is measured against
                    // this number, so labelling it fair would claim the market is
                    // mispriced when the calibrated reference is the book's mid.
                    Metric(label: "Model", value: Fmt.pct(window.snapshot?.pUp), size: 15)
                    Metric(label: "Ask", value: Fmt.cents(window.snapshot?.upAsk), size: 15, tint: Palette.warn)
                    // Show the edge the server endorsed when it endorsed one. The
                    // raw arithmetic stays positive on declined windows, so quoting
                    // it here would advertise a number the advisor does not stand by.
                    Metric(label: "Edge",
                           value: Fmt.signedCents(
                               window.snapshot?.serverValidatedTrade == true
                                   ? window.snapshot?.advice?.edge
                                   : window.snapshot?.bestEdge
                           ),
                           size: 15, tint: v.tint)
                }
            }
        }
    }

    private func mathCard(_ s: MarketSnapshot?, verdict: Verdict) -> some View {
        let side = verdict.side
        let ask = side == "DOWN" ? s?.downAsk : s?.upAsk
        let modelP = side == "DOWN" ? (s?.pUp.map { 1 - $0 }) : s?.pUp
        let bookP = side == "DOWN" ? (s?.bookUp.map { 1 - $0 }) : s?.bookUp
        let fee = MarketSnapshot.fee(price: ask)
        let breakeven = (ask ?? 0) + (fee ?? 0)
        let roi = (modelP ?? 0) > 0 ? (verdict.edge / max(ask ?? 1, 0.0001)) : 0

        return Panel {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: "Edge maths", detail: side ?? "—")
                Rule().padding(.vertical, 6)

                KeyRow(key: "Model probability", value: Fmt.pct(modelP, digits: 1))
                // The calibrated reference. On 1,822 held-out windows the book's
                // mid beat the model on Brier 0.1365 to 0.2335.
                KeyRow(key: "Book mid (calibrated)", value: Fmt.pct(bookP, digits: 1),
                       tint: Palette.up.opacity(0.95))
                KeyRow(key: "Market ask", value: Fmt.cents(ask), tint: Palette.warn)
                KeyRow(key: "Taker fee (0.07·p·(1−p))", value: Fmt.cents(fee), tint: Palette.dim)
                KeyRow(key: "Breakeven price", value: Fmt.cents(breakeven), tint: Palette.dim)
                Rule().padding(.vertical, 6)
                KeyRow(key: "Model edge per share", value: Fmt.signedCents(verdict.edge), tint: verdict.tint)
                KeyRow(key: "Return on stake", value: Fmt.signedPct(roi), tint: verdict.tint)
                // Resting a bid here pays no taker fee — the only structurally +EV
                // action measured. A taker buy at the ask nets negative by half the
                // spread plus the fee.
                KeyRow(key: "Maker bid target (≤)", value: Fmt.cents(bookP), tint: Palette.up)
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
        model: \(Fmt.pct(s?.pUp))  book: \(Fmt.pct(s?.bookUp))  ask: \(Fmt.cents(s?.upAsk))
        edge: \(Fmt.signedCents(v.edge))
        beat: \(Fmt.price(s?.beat))  spot: \(Fmt.price(s?.spot))
        maker bid target: bid <= \(Fmt.cents(v.side == "DOWN" ? s?.bookUp.map { 1 - $0 } : s?.bookUp))
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
            // Model-based by definition: the server computes edge_up/edge_down
            // from p_up. Say so, or the card implies the market is mispriced when
            // the book's own mid — the better-calibrated reference — may disagree.
            let modelP = picked == "UP" ? s?.pUp : s?.pUp.map { 1 - $0 }
            let bookP = picked == "UP" ? s?.bookUp : s?.bookUp.map { 1 - $0 }
            let ask = picked == "UP" ? s?.upAsk : s?.downAsk
            subline = "Model \(Fmt.pct(modelP)) vs book \(Fmt.pct(bookP)) vs ask "
                + "\(Fmt.cents(ask)) — clears the taker fee."
        } else {
            headline = "NO EDGE"
            subline = "Both sides sit at or above the model's probability net of fees."
        }
    }
}
