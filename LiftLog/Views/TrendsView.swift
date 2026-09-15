import SwiftUI
import Charts

/// Per-lift progression: a chart over time plus short- and long-term change.
/// Generic and lift-focused — no personal goals or targets.
struct TrendsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize

    // Persisted so Trends reopens on the lift you last looked at.
    @AppStorage("trends_exercise") private var exercise = ""
    /// Three questions, three views: how one lift is going, how every lift
    /// stands, and how the training as a whole is going.
    private enum Mode: String, CaseIterable, Identifiable {
        case lift, lifts, volume
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lift: return "Lift"
            case .lifts: return "All lifts"
            case .volume: return "Volume"
            }
        }
    }
    @AppStorage("trends_mode") private var mode: Mode = .lift
    @AppStorage("muscle_map") private var muscleMap = MuscleMap()
    @State private var metric: Analytics.Metric = .topSet
    /// Where a finger is on the chart's x-axis, if it's on it at all.
    @State private var scrub: Date?
    @State private var showingPicker = false

    /// Everything the tab draws, computed once per change of the log or the
    /// selection rather than on every body pass: a scrub redraws at touch
    /// rate, and each of these walks the whole log.
    private struct Figures {
        var exercises: [String] = []
        var metrics: [Analytics.Metric] = [.topSet]
        var series: [TrendPoint] = []
        var recent: TrendChange?
        var allTime: TrendChange?
        var dose: DoseResponse?
        var weeks: [Analytics.TrainingWeek] = []
        var weekly: [MuscleMap.Credits] = []
        var unmapped: [String] = []
        var board: [Analytics.LiftSummary] = []
    }
    @State private var figures = Figures()

    /// How much of a long history the lift chart shows at once; the rest is a
    /// flick away. Four months is a training block.
    private let window: TimeInterval = 120 * 86_400

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.sessions.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 12) {
                            Barbell(height: 38)
                            Text("No data yet")
                        }
                    } description: {
                        Text("A lift's chart appears after its second session; sets per muscle after the first week. Both come from the log alone.")
                    }
                    .padding(.top, 80)
                } else {
                    VStack(spacing: 16) {
                        Picker("view", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        switch mode {
                        case .lift:
                            exercisePicker
                            if figures.metrics.count > 1 { metricPicker }
                            chartCard
                            statsRow
                            if let dose = figures.dose {
                                doseCard(dose)
                            }
                        case .lifts:
                            liftsCard
                        case .volume:
                            weeksCard
                            musclesCard
                        }
                    }
                    .padding()
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Theme.backgroundView)
            .navigationTitle("Trends")
            .refreshable { await store.load() }
            .onAppear {
                ensureSelection()
                recompute()
            }
            .onChange(of: store.sessions) { _, _ in
                ensureSelection()
                recompute()
            }
            .onChange(of: exercise) { _, _ in
                scrub = nil
                clampMetric()
                recompute()
            }
            .onChange(of: metric) { _, _ in
                scrub = nil
                recompute()
            }
            .onChange(of: muscleMap) { _, _ in recompute() }
            .onChange(of: mode) { _, _ in scrub = nil }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(history: figures.exercises, library: false) { exercise = $0 }
            }
        }
    }

    // MARK: - Controls

    /// A pill, like the bar menu on Log and the date on History: the chart is
    /// the loudest thing on this screen, not the control above it.
    private var exercisePicker: some View {
        Button { showingPicker = true } label: {
            HStack(spacing: 6) {
                Text(exercise.isEmpty ? "choose a lift" : Theme.readableName(exercise))
                    .font(.headline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Lift")
        .accessibilityValue(Theme.readableName(exercise))
    }

    private var metricPicker: some View {
        Picker("Metric", selection: $metric) {
            ForEach(figures.metrics) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Chart

    private var chartCard: some View {
        let series = figures.series
        return CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(metric.rawValue.lowercased()) · \(metric.unit)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let last = series.last?.date {
                        Text("last \(last, format: .dateTime.day().month(.abbreviated)) · \(series.count) sessions")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }

                if series.count >= 2 {
                    liftChart(series)
                        .frame(height: 240)
                    Text("drag along the line to read a session · tap the reading to open that day")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("Need at least two sessions of this lift to chart a trend.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(height: 240, alignment: .center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// The chart, and a window onto it when the history is longer than one:
    /// two years of sessions were one smear at a fixed width, and the newest
    /// block is what a lifter opens the tab for.
    @ViewBuilder
    private func liftChart(_ series: [TrendPoint]) -> some View {
        let chart = Chart { liftMarks(series) }
            .chartXSelection(value: $scrub)
            .chartYScale(domain: yDomain(series))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .accessibilityLabel(chartDescription(series))

        if let first = series.first?.date, let last = series.last?.date,
           last.timeIntervalSince(first) > window {
            // Room after the newest point so it isn't pinned to the edge.
            let end = last.addingTimeInterval(window * 0.08)
            chart
                .chartXScale(domain: first...end)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: window)
                .chartScrollPosition(initialX: end.addingTimeInterval(-window))
        } else {
            chart
        }
    }

    @ChartContentBuilder
    private func liftMarks(_ series: [TrendPoint]) -> some ChartContent {
        ForEach(series) { point in
            LineMark(x: .value("Date", point.date),
                     y: .value(metric.rawValue, point.value))
                // Monotone, not Catmull-Rom: on sparse training data the
                // latter overshoots and draws a peak that was never lifted.
                .interpolationMethod(.monotone)
                .foregroundStyle(.tint)
            PointMark(x: .value("Date", point.date),
                      y: .value(metric.rawValue, point.value))
                .foregroundStyle(.tint)
                .symbolSize(28)
        }
        // Drag along the line to read a session off it.
        if let picked = scrubbed(in: series) {
            RuleMark(x: .value("Date", picked.date))
                .foregroundStyle(.secondary.opacity(0.35))
                .annotation(position: .top, spacing: 6,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    reading(picked)
                }
            PointMark(x: .value("Date", picked.date),
                      y: .value(metric.rawValue, picked.value))
                .foregroundStyle(.tint)
                .symbolSize(90)
        }
    }

    /// The session under the finger: the value, the day, the sets as logged —
    /// and a tap opens that day on the Log tab, the same jump History makes.
    private func reading(_ picked: TrendPoint) -> some View {
        VStack(spacing: 2) {
            Text("\(WorkSet.formatWeight(picked.value)) \(metric.unit)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
            Text(picked.date, format: .dateTime.day().month(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !picked.tokens.isEmpty {
                Text(picked.tokens)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Label("open", systemImage: "arrow.up.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            store.requestEdit(exercise: picked.name.isEmpty ? exercise : picked.name, on: picked.date)
        }
    }

    /// The logged point nearest the finger — a drag snaps to real sessions,
    /// never interpolates a value that wasn't lifted.
    private func scrubbed(in series: [TrendPoint]) -> TrendPoint? {
        guard let scrub else { return nil }
        return series.min {
            abs($0.date.timeIntervalSince(scrub)) < abs($1.date.timeIntervalSince(scrub))
        }
    }

    /// The y-axis with a floor on its span: two sessions at 100 and 102.5
    /// are a small step and should draw as one, not as a cliff.
    private func yDomain(_ series: [TrendPoint]) -> ClosedRange<Double> {
        let values = series.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let minSpan = metric == .maxReps ? 6.0 : max(10, hi * 0.15)
        let half = max(hi - lo, minSpan) / 2 * 1.15
        let mid = (lo + hi) / 2
        let lower = lo >= 0 ? max(0, mid - half) : mid - half
        return lower...max(mid + half, lower + 1)
    }

    private func chartDescription(_ series: [TrendPoint]) -> String {
        guard let first = series.first, let last = series.last else { return metric.rawValue }
        let from = first.date.formatted(.dateTime.day().month(.abbreviated).year())
        let to = last.date.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(metric.rawValue) over \(series.count) sessions from \(from) to \(to), " +
            "from \(WorkSet.formatWeight(first.value)) to \(WorkSet.formatWeight(last.value)) \(metric.unit)"
    }

    // MARK: - Stats

    private var statsRow: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) { statTiles }
            } else {
                HStack(spacing: 12) { statTiles }
            }
        }
    }

    @ViewBuilder
    private var statTiles: some View {
        statTile(title: "Short-term", subtitle: "last 3 weeks", change: figures.recent,
                 empty: "no two sessions in the window")
        statTile(title: "Long-term", subtitle: "all time", change: figures.allTime,
                 empty: "not enough data")
    }

    private func statTile(title: String, subtitle: String, change: TrendChange?, empty: String) -> some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.lowercased()).font(.caption).foregroundStyle(.secondary)
                if let c = change {
                    HStack(spacing: 4) {
                        Image(systemName: c.isUp ? "arrow.up.right" : (c.isFlat ? "arrow.right" : "arrow.down.right"))
                        Text(formatted(c.delta) + " \(metric.unit)")
                            .contentTransition(.numericText())
                    }
                    .font(.title3.weight(.bold))
                    .animation(.snappy, value: c.delta)
                    // Accent for up, muted for down. System green/red read as traffic
                    // lights against steel, and red should mean an error, not a dip.
                    .foregroundStyle(c.isUp ? Theme.accent : Color.secondary)
                    if let percent = c.percent {
                        Text(String(format: "%+.0f%%", percent))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("—").font(.title3.weight(.bold)).foregroundStyle(.secondary)
                    Text(empty).font(.footnote).foregroundStyle(.secondary)
                }
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Dose and response

    /// The lift's own weekly sets against every set its main muscle got, on
    /// the same weeks, and one sentence naming the lever. The weekly best
    /// isn't drawn again here: the chart above already is that line.
    private func doseCard(_ dose: DoseResponse) -> some View {
        let lift = Theme.readableName(dose.exercise)
        let top = max(DoseResponse.band.upperBound + 2, (dose.weeks.map(\.sets).max() ?? 0) + 2)
        return PanelBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("work and result")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("sets a week, last \(dose.weeks.count) weeks")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                // Work: this lift's own sets inside every set for its main
                // muscle, against the band the total is judged by. The lift's
                // bar is narrower so an overshoot — a lift whose main share is
                // a half — shows as one rather than hiding the bar behind it.
                Chart {
                    RectangleMark(yStart: .value("low", DoseResponse.band.lowerBound),
                                  yEnd: .value("high", DoseResponse.band.upperBound))
                        .foregroundStyle(Theme.accent.opacity(0.12))
                    ForEach(dose.weeks) { week in
                        BarMark(x: .value("Week", week.start), y: .value("Muscle sets", week.sets), width: .ratio(0.8))
                            .foregroundStyle(Color.secondary.opacity(0.22))
                            .cornerRadius(3)
                        BarMark(x: .value("Week", week.start), y: .value("Lift sets", Double(week.liftSets)), width: .ratio(0.45))
                            .foregroundStyle(Theme.accent)
                            .cornerRadius(3)
                    }
                }
                .chartYScale(domain: 0...top)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 110)
                .accessibilityLabel("\(lift) sets a week and \(dose.muscle.rawValue) sets in all, last \(dose.weeks.count) weeks")
                .accessibilityValue(dose.summary)

                HStack(spacing: 14) {
                    legendSwatch(Theme.accent, "\(lift)")
                    legendSwatch(Color.secondary.opacity(0.22), "\(dose.muscle.rawValue) in all")
                    legendSwatch(Theme.accent.opacity(0.14), "\(Int(DoseResponse.band.lowerBound))–\(Int(DoseResponse.band.upperBound)) band")
                }

                Text(dose.summary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if dose.verdict != .tooEarly {
                    Button {
                        store.requestCoach(dose.coachQuestion())
                    } label: {
                        Label("Ask the coach about this", systemImage: "bubble.left.and.text.bubble.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Every lift

    /// The whole log, one row a lift: what was done last, the standing best
    /// and how long it has stood, how often lately. The same numbers the
    /// coach's digest gets — now the lifter gets them too. Tap a row to chart it.
    private var liftsCard: some View {
        let today = Date()
        let calendar = Calendar.current
        return PanelBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("every lift · last done first")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("best · how long it has stood")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.bottom, 6)
                ForEach(figures.board) { row in
                    Button {
                        exercise = row.name
                        mode = .lift
                    } label: {
                        boardRow(row, today: today, calendar: calendar)
                    }
                    .buttonStyle(.plain)
                    if row.id != figures.board.last?.id { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func boardRow(_ row: Analytics.LiftSummary, today: Date, calendar: Calendar) -> some View {
        let since = row.daysSinceLast(today: today, calendar: calendar)
        let bestAgo = row.daysSinceBest(today: today, calendar: calendar)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Theme.readableName(row.name))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(ago(since)) · \(row.lastTokens)")
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(row.sessionsInFourWeeks) in 4 weeks · \(row.sessionsEver) ever")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.best?.token ?? "—")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if let bestAgo {
                    // Recent in the accent, an old one muted: which lift has
                    // gone longest without a record reads off the column.
                    Text(bestAgo == 0 ? "today" : ago(bestAgo))
                        .font(.caption2)
                        .foregroundStyle(bestAgo <= 42 ? Theme.accent : Color.secondary)
                        .monospacedDigit()
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Theme.readableName(row.name))
        .accessibilityValue("last \(ago(since)), \(row.lastTokens); best \(row.best?.token ?? "none")"
                            + (bestAgo.map { ", \(ago($0))" } ?? "")
                            + "; \(row.sessionsInFourWeeks) sessions in four weeks")
    }

    private func ago(_ days: Int) -> String {
        days == 0 ? "today" : (days == 1 ? "yesterday" : "\(days) days ago")
    }

    // MARK: - Weeks

    /// Every day of the last few months as a dot: filled when you trained,
    /// deeper the more sets you did. A missed week is a blank column, visible
    /// without asking anyone.
    private var weeksCard: some View {
        let weeks = figures.weeks
        // A Monday with nothing logged yet shows the week just finished — and
        // compares it with the four before it, not with itself.
        let thisWeek = weeks.last
        let showingThisWeek = (thisWeek?.sessions ?? 0) > 0
        let featured = showingThisWeek ? thisWeek : weeks.dropLast().last
        let prior = showingThisWeek ? weeks.dropLast() : weeks.dropLast(2)
        let lastFour = prior.suffix(4)
        let perWeek = lastFour.isEmpty ? 0 : Double(lastFour.map(\.sessions).reduce(0, +)) / Double(lastFour.count)
        let setsPerWeek = lastFour.isEmpty ? 0 : Double(lastFour.map(\.sets).reduce(0, +)) / Double(lastFour.count)
        let count = featured?.sessions ?? 0

        return PanelBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("training days")
                    .font(.caption).foregroundStyle(.secondary)
                TrainingGrid(weeks: weeks)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(showingThisWeek ? "this week" : "last week").font(.caption2).foregroundStyle(.tertiary)
                        Text(count == 1 ? "1 session" : "\(count) sessions")
                            .font(.subheadline.weight(.bold))
                            .contentTransition(.numericText())
                        Text("\(featured?.sets ?? 0) sets")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("previous 4 weeks").font(.caption2).foregroundStyle(.tertiary)
                        Text(String(format: "%.1f / week", perWeek))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                        Text(String(format: "%.0f sets / week", setsPerWeek))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sets per muscle

    /// Sets per muscle as bars, not a table: the week that matters against a
    /// 10–20 band, with a thin marker for the four-week average. This week
    /// while it has sets in it, else last week — a Monday shows the week just
    /// done, not a column of dashes.
    private var musclesCard: some View {
        let weekly = figures.weekly
        let current = weekly.last ?? [:]
        let thisWeekHasSets = current.values.reduce(0, +) > 0
        let shown = thisWeekHasSets ? current : (weekly.dropLast().last ?? [:])
        // The average is of the weeks before the one shown, never including it.
        let previous = Array((thisWeekHasSets ? weekly.dropLast() : weekly.dropLast(2)).suffix(4))
        let groups = MuscleGroup.ordered.filter { g in
            (shown[g] ?? 0) > 0 || previous.contains { ($0[g] ?? 0) > 0 }
        }
        let unmapped = figures.unmapped
        let scale = max(20, groups.map { shown[$0] ?? 0 }.max() ?? 0,
                        groups.map { avg($0, in: previous) }.max() ?? 0)

        return PanelBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("sets per muscle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(thisWeekHasSets ? "this week so far" : "last week")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }

                if groups.isEmpty {
                    Text("Nothing counted yet. Lifts the app doesn't know are assigned in Settings ▸ Muscles.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(groups) { group in
                            muscleBar(group.rawValue, sets: shown[group] ?? 0,
                                      average: avg(group, in: previous), scale: scale)
                        }
                    }
                    HStack(spacing: 14) {
                        legendSwatch(Theme.accent.opacity(0.14), "\(Int(DoseResponse.band.lowerBound))–\(Int(DoseResponse.band.upperBound)) sets a week")
                        legendSwatch(Color.primary.opacity(0.55), "4-week average", thin: true)
                    }
                    .padding(.top, 2)
                }

                if !unmapped.isEmpty {
                    Text("not counted: " + unmapped.map { Theme.readableName($0) }.joined(separator: ", ")
                         + " — assign in Settings ▸ Muscles")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func avg(_ group: MuscleGroup, in weeks: [MuscleMap.Credits]) -> Double {
        guard !weeks.isEmpty else { return 0 }
        return weeks.map { $0[group] ?? 0 }.reduce(0, +) / Double(weeks.count)
    }

    /// One muscle: the name, a bar for the week against the band, the number.
    private func muscleBar(_ name: String, sets: Double, average: Double, scale: Double) -> some View {
        let low = DoseResponse.band.lowerBound
        let high = DoseResponse.band.upperBound
        return HStack(spacing: 10) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 88, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                let x = { (v: Double) in CGFloat(min(v, scale) / scale) * w }
                ZStack(alignment: .leading) {
                    // The band a programme usually aims for.
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: max(0, x(high) - x(low)))
                        .offset(x: x(low))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(sets > 0 ? Theme.accent : Color.clear)
                        .frame(width: max(sets > 0 ? 4 : 0, x(sets)))
                    if average > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 2, height: 18)
                            .offset(x: x(average) - 1)
                    }
                }
                .frame(height: 14)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)
            Text(compact(sets))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(sets > 0 ? Color.primary : Color.secondary)
                .frame(width: 34, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(compact(sets)) sets this week, \(compact(average)) a week on average")
    }

    private func legendSwatch(_ color: Color, _ label: String, thin: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: thin ? 2 : 14, height: thin ? 12 : 8)
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func compact(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func formatted(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        let s = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return v >= 0 ? "+\(s)" : s
    }

    /// One name per lift, newest spelling, whatever the log has called it.
    private func knownLifts() -> [String] {
        var seen = Set<String>()
        return store.knownExercises.filter { seen.insert(MuscleMap.canonical($0)).inserted }.sorted()
    }

    private func ensureSelection() {
        let names = knownLifts()
        // Keep a valid selection; when there isn't one, default to the lift you log
        // most (a better proxy for "the one I care about" than alphabetical order).
        if let match = names.first(where: { Analytics.matches($0, exercise) }) {
            if match != exercise { exercise = match }
        } else {
            exercise = mostLogged(among: names)
        }
        clampMetric()
    }

    /// The exercise appearing in the most sessions (ties broken alphabetically).
    private func mostLogged(among names: [String]) -> String {
        let best = Analytics.liftSummaries(in: store.sessions).max { a, b in
            a.sessionsEver != b.sessionsEver ? a.sessionsEver < b.sessionsEver : a.name > b.name
        }
        return best.flatMap { top in names.first { Analytics.matches($0, top.name) } } ?? names.first ?? ""
    }

    private func clampMetric() {
        let metrics = Analytics.availableMetrics(exercise, in: store.sessions)
        if !metrics.contains(metric) { metric = metrics.first ?? .topSet }
    }

    private func recompute() {
        var f = Figures()
        f.exercises = knownLifts()
        f.board = Analytics.liftSummaries(in: store.sessions)
        f.weeks = Analytics.weekGrid(weeks: 26, in: store.sessions)
        f.weekly = muscleMap.weeklySets(weeks: 6, in: store.sessions)
        f.unmapped = muscleMap.unmapped(in: store.sessions)
        if !exercise.isEmpty {
            f.metrics = Analytics.availableMetrics(exercise, in: store.sessions)
            let shown = f.metrics.contains(metric) ? metric : (f.metrics.first ?? .topSet)
            f.series = Analytics.series(exercise, metric: shown, in: store.sessions)
            f.recent = Analytics.change(f.series, sinceDays: 21)
            f.allTime = Analytics.change(f.series)
            f.dose = DoseResponse.make(for: exercise, in: store.sessions, map: muscleMap)
        }
        figures = f
    }
}

/// Columns are weeks, oldest on the left; rows are Monday down to Sunday.
/// Only the weeks since the first logged session (eight at least), so a new
/// log isn't a wall of empty squares, and the dots grow to fill the width.
private struct TrainingGrid: View {
    let weeks: [Analytics.TrainingWeek]

    private let gap: CGFloat = 5
    private let labelWidth: CGFloat = 18
    private let rowLabels = ["M", "", "W", "", "F", "", ""]

    var body: some View {
        let firstTrained = weeks.firstIndex { $0.sessions > 0 } ?? max(0, weeks.count - 8)
        let relevant = Array(weeks.suffix(max(8, weeks.count - firstTrained)))
        let dot = dotSize(for: relevant.count)

        GeometryReader { geo in
            let available = geo.size.width - labelWidth
            let fit = max(1, Int((available + gap) / (dot + gap)))
            let shown = Array(relevant.suffix(fit))
            let heaviest = shown.flatMap(\.days).compactMap { $0?.sets }.max() ?? 0
            let today = shown.last?.days.compactMap { $0 }.last?.key

            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(rowLabels[row])
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: labelWidth - gap, height: dot)
                    }
                }
                ForEach(shown) { week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(week.days[row], heaviest: heaviest,
                                 isToday: week.days[row]?.key == today, size: dot)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Training days")
            .accessibilityValue("\(shown.map(\.sessions).reduce(0, +)) sessions in the last \(shown.count) weeks")
        }
        .frame(height: 7 * dot + 6 * gap)
    }

    /// Big dots for a young log, smaller as the weeks pile up.
    private func dotSize(for columns: Int) -> CGFloat {
        columns <= 8 ? 20 : (columns <= 14 ? 16 : 12)
    }

    private func cell(_ day: Analytics.TrainingDay?, heaviest: Int, isToday: Bool, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(fill(day, heaviest: heaviest))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 1.5)
                }
            }
            .frame(width: size, height: size)
    }

    /// Blank for the future, faint for a rest day, accent for a session — the
    /// more sets in the day, the deeper the accent.
    private func fill(_ day: Analytics.TrainingDay?, heaviest: Int) -> Color {
        guard let day else { return .clear }
        guard let sets = day.sets else { return Color.secondary.opacity(0.14) }
        let intensity = heaviest > 0 ? Double(sets) / Double(heaviest) : 1
        return Theme.accent.opacity(0.45 + 0.55 * intensity)
    }
}

/// The raised surface — the chart.
private struct CardBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.glassCard() }
}

/// The flat surface — the stat tiles beneath it.
private struct PanelBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.panel() }
}
