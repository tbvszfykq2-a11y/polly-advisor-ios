import SwiftUI
import UIKit

// MARK: - Signals

struct SignalsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", buys = "Buys", exits = "Exits"
        var id: String { rawValue }
    }

    private var filtered: [Advice] {
        switch filter {
        case .all:   return model.advice
        case .buys:  return model.advice.filter { !$0.isExit }
        case .exits: return model.advice.filter { $0.isExit }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 9) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 2)

                    if filtered.isEmpty {
                        Panel {
                            EmptyPanel(
                                icon: "bolt.slash",
                                title: "No signals yet",
                                message: "The engine only records a signal when a side clears the "
                                    + "taker fee. Quiet boards are expected."
                            )
                        }
                    } else {
                        ForEach(filtered) { a in
                            SignalRow(advice: a)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Signals")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
        }
    }
}

struct SignalRow: View {
    let advice: Advice

    private var sideTint: Color {
        (advice.side ?? "").uppercased() == "UP" ? Palette.up : Palette.down
    }

    private var stamp: String {
        guard let d = advice.date else { return "—" }
        return d.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Panel(padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(advice.tint)
                    .frame(width: 2.5)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(AssetStyle.ticker(advice.asset))
                            .font(.label(12, .semibold))
                            .foregroundStyle(Palette.text)
                        SideChip(text: (advice.kind ?? "SIGNAL").uppercased(), tint: advice.tint)
                        if let side = advice.side, !side.isEmpty {
                            SideChip(text: side, tint: sideTint)
                        }
                        Spacer(minLength: 4)
                        Text(stamp)
                            .font(.mono(9))
                            .foregroundStyle(Palette.faint)
                    }

                    if let reason = advice.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.label(11))
                            .foregroundStyle(Palette.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 14) {
                        mini("PRICE", Fmt.cents(advice.price))
                        mini("EDGE", Fmt.signedCents(advice.edge), tint: Palette.up)
                        mini("SIZE", advice.sizeShares.map { "\($0)" } ?? "—")
                        mini("LEFT", Fmt.clock(advice.tRemaining))
                    }
                }
            }
        }
    }

    private func mini(_ label: String, _ value: String, tint: Color = Palette.dim) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.mono(7.5, .semibold))
                .tracking(0.4)
                .foregroundStyle(Palette.faint)
            Text(value)
                .font(.mono(10.5, .medium))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Edge / scorecard

struct EdgeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let sc = model.scorecard {
                        scorecardPanel(sc)
                        bucketPanel(sc)
                        caveatPanel(sc)
                    } else {
                        Panel {
                            EmptyPanel(
                                icon: "chart.line.downtrend.xyaxis",
                                title: "Scorecard unavailable",
                                message: "The advisor has not returned graded history yet."
                            )
                        }
                    }

                    execPanel
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Edge")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
        }
    }

    private func scorecardPanel(_ sc: Scorecard) -> some View {
        let rate = sc.hitRate ?? 0
        let tint = rate >= 0.5 ? Palette.up : (rate >= 0.3 ? Palette.warn : Palette.down)

        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        MicroLabel(text: "Graded hit rate")
                        Text(Fmt.pct(rate, digits: 1))
                            .font(.mono(30, .bold))
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        MicroLabel(text: "Window")
                        Text("\(sc.windowDays ?? 7) days")
                            .font(.mono(12, .medium))
                            .foregroundStyle(Palette.dim)
                        MicroLabel(text: "Graded")
                        Text(Fmt.compact(sc.n))
                            .font(.mono(12, .medium))
                            .foregroundStyle(Palette.dim)
                    }
                }
                Rule()
                Text("Share of recorded signals whose advice matched the settled outcome.")
                    .font(.label(10.5))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bucketPanel(_ sc: Scorecard) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "By confidence bucket", detail: "n / hit")
                Rule().padding(.vertical, 2)

                ForEach(sc.orderedBuckets, id: \.key) { bucket in
                    BucketRow(name: bucket.key, stat: bucket.stat)
                }
            }
        }
    }

    private func caveatPanel(_ sc: Scorecard) -> some View {
        let preopen = sc.byConf?["PREOPEN"]
        let dead = (preopen?.n ?? 0) > 50 && (preopen?.hitRate ?? 0) < 0.05

        return Group {
            if dead {
                Panel {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.warn)
                        Text("Pre-open signals are \(Fmt.pct(preopen?.hitRate, digits: 1)) over "
                             + "\(Fmt.compact(preopen?.n)) graded windows. Treat them as noise and "
                             + "weight in-window signals instead.")
                            .font(.label(11))
                            .foregroundStyle(Palette.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var execPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    MicroLabel(text: "Execution")
                    Spacer()
                    SideChip(
                        text: (model.exec?.enabled ?? false) ? "ARMED" : "ADVISORY",
                        tint: (model.exec?.enabled ?? false) ? Palette.warn : Palette.dim
                    )
                }
                Rule()
                KeyRow(key: "Client attached", value: (model.exec?.attached ?? false) ? "yes" : "no")
                KeyRow(key: "Dry run", value: (model.exec?.dryRun ?? true) ? "on" : "off")
                KeyRow(key: "Ready", value: (model.exec?.ready ?? false) ? "yes" : "no",
                       tint: (model.exec?.ready ?? false) ? Palette.up : Palette.faint)
                if let reason = model.exec?.reason {
                    Text(reason)
                        .font(.mono(9.5))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }
}

struct BucketRow: View {
    let name: String
    let stat: ConfStat

    private var rate: Double { stat.hitRate ?? 0 }
    private var tint: Color {
        rate >= 0.5 ? Palette.up : (rate >= 0.3 ? Palette.warn : Palette.down)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.mono(10, .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(Fmt.compact(stat.n)) · \(Fmt.pct(rate, digits: 0))")
                    .font(.mono(9.5))
                    .foregroundStyle(Palette.faint)
                Text(Fmt.cents(stat.avgPrice))
                    .font(.mono(9.5))
                    .foregroundStyle(Palette.dim)
                    .frame(width: 46, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05))
                    Capsule()
                        .fill(tint.opacity(0.75))
                        .frame(width: max(2, geo.size.width * min(1, max(0, rate))))
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                SettingsForm(onSaved: nil)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SettingsForm: View {
    @EnvironmentObject private var model: AppModel
    var onSaved: (() -> Void)?

    @State private var testing = false
    @State private var result: String?
    @State private var resultOK = false

    var body: some View {
        VStack(spacing: 12) {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Advisor endpoint")
                    Rule()

                    field("Server", text: $model.serverURL,
                          placeholder: "http://10.200.200.1:8793",
                          keyboard: .URL)
                    field("Username", text: $model.username, placeholder: "advisor")
                    secureField("Password", text: $model.password)

                    HStack {
                        Text("Poll interval")
                            .font(.label(11.5))
                            .foregroundStyle(Palette.dim)
                        Spacer()
                        Text("\(Int(model.pollSeconds))s")
                            .font(.mono(11.5, .medium))
                            .foregroundStyle(Palette.text)
                        Stepper("", value: $model.pollSeconds, in: 1...10, step: 1)
                            .labelsHidden()
                    }
                    .padding(.top, 2)
                }
            }

            Panel {
                VStack(spacing: 9) {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack(spacing: 7) {
                            if testing {
                                ProgressView().scaleEffect(0.7)
                            }
                            Text(testing ? "Testing…" : "Test connection")
                                .font(.label(12.5, .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .foregroundStyle(Palette.text)
                    .disabled(testing)

                    if let result {
                        Text(result)
                            .font(.mono(9.5))
                            .foregroundStyle(resultOK ? Palette.up : Palette.down)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        model.saveSettings()
                        model.reconnect()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onSaved?()
                    } label: {
                        Text("Save & connect")
                            .font(.label(12.5, .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Palette.accent.opacity(0.18))
                            )
                    }
                    .foregroundStyle(Palette.accent)
                    .disabled(model.serverURL.isEmpty || model.password.isEmpty)
                    .opacity((model.serverURL.isEmpty || model.password.isEmpty) ? 0.45 : 1)
                }
            }

            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "About")
                    Rule()
                    KeyRow(key: "Version", value: "1.0.0 (1)")
                    KeyRow(key: "Mode", value: (model.state?.mode ?? "—").uppercased())
                    KeyRow(key: "Assets", value: (model.state?.assets ?? []).map { $0.uppercased() }
                        .joined(separator: " "))
                    KeyRow(key: "Storage", value: Fmt.bytes(model.state?.store?.bytes))
                    Text("Polly Advisor is read-only. It never places an order; every trade is "
                         + "executed by you on your own device.")
                        .font(.label(10.5))
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func runTest() async {
        testing = true
        result = nil
        let outcome = await model.testConnection()
        switch outcome {
        case .success(let latency):
            resultOK = true
            result = String(format: "Connected in %.0f ms", latency * 1000)
        case .failure(let error):
            resultOK = false
            result = (error as? PollyError)?.errorDescription ?? error.localizedDescription
        }
        testing = false
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.label(11.5))
                .foregroundStyle(Palette.dim)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Palette.faint))
                .font(.mono(11.5))
                .foregroundStyle(Palette.text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 0.75)
                )
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.label(11.5))
                .foregroundStyle(Palette.dim)
            SecureField("", text: text, prompt: Text("required").foregroundStyle(Palette.faint))
                .font(.mono(11.5))
                .foregroundStyle(Palette.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 0.75)
                )
        }
    }
}
