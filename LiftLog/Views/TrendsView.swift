import SwiftUI
import Charts

/// Per-lift progression: a chart over time plus short- and long-term change.
/// Generic and lift-focused — no personal goals or targets.
struct TrendsView: View {
    @EnvironmentObject var store: Store

    // Persisted so Trends reopens on the lift you last looked at.
    @AppStorage("trends_exercise") private var exercise = ""
    /// Two questions, two views: how a lift is going, and how the training
    /// as a whole is going. One screen tried to answer both and the exercise
    /// picker at the top made the second look like it belonged to the first.
    private enum Mode: String, CaseIterable, Identifiable {
        case lift, volume
        var id: String { rawValue }
        var title: String { self == .lift ? "Lift" : "Volume" }
    }
    @AppStorage("trends_mode") private var mode: Mode = .lift
    @AppStorage("muscle_map") private var muscleMap = MuscleMap()
    @State private var metric: Analytics.Metric = .topSet
    /// Where a finger is on the chart's x-axis, if it's on it at all.
    @State private var scrub: Date?

    /// The logged point nearest the finger — a drag snaps to real sessions,
    /// never interpolates a value that wasn't lifted.
    private var scrubbed: TrendPoint? {
        guard let scrub else { return nil }
        return series.min {
            abs($0.date.timeIntervalSince(scrub)) < abs($1.date.timeIntervalSince(scrub))
        }
    }

    private var exercises: [String] { store.knownExercises.sorted() }

    private var availableMetrics: [Analytics.Metric] {
        Analytics.availableMetrics(exercise, in: store.sessions)
    }

    private var series: [TrendPoint] {
        Analytics.series(exercise, metric: metric, in: store.sessions)
    }

    private var recent: TrendChange? { Analytics.change(series, sinceDays: 21) }
    private var allTime: TrendChange? { Analytics.change(series) }

    /// Half a year of weeks; the grid shows as many of the newest as fit.
    private var weeks: [Analytics.TrainingWeek] {
        Analytics.weekGrid(weeks: 26, in: store.sessions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if exercises.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 12) {
                            Barbell(height: 38)
                            Text("No data yet")
                        }
                    } description: {
                        Text("Log some workouts to see trends.")
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
                            if availableMetrics.count > 1 { metricPicker }
                            chartCard
                            statsRow
                            if let dose = DoseResponse.make(for: exercise, in: store.sessions, map: muscleMap) {
                                doseCard(dose)
                            }
                        case .volume:
                            weeksCard
                            musclesCard
                        }
                    }
                    .padding()
                }
            }
            .background(Theme.backgroundView)
            .navigationTitle("Trends")
            .refreshable { await store.load() }
            .onAppear(perform: ensureSelection)
            .onChange(of: exercise) { _, _ in clampMetric() }
        }
    }

    // MARK: - Controls

    private var exercisePicker: some View {
        Menu {
            Picker("Exercise", selection: $exercise) {
                ForEach(exercises, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack {
                Text(exercise.isEmpty ? "choose exercise" : Theme.readableName(exercise))
                    .font(.title3.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.footnote)
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            )
        }
    }

    private var metricPicker: some View {
        Picker("Metric", selection: $metric) {
            ForEach(availableMetrics) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Chart

    private var chartCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(metric.rawValue.lowercased() + " over time")
                    .font(.caption).foregroundStyle(.secondary)

                if series.count >= 2 {
                    Chart {
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
                        if let picked = scrubbed {
                            RuleMark(x: .value("Date", picked.date))
                                .foregroundStyle(.secondary.opacity(0.35))
                                .annotation(position: .top, spacing: 6,
                                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                    VStack(spacing: 2) {
                                        Text("\(WorkSet.formatWeight(picked.value)) \(metric.unit)")
                                            .font(.caption.weight(.bold))
                                            .monospacedDigit()
                                        Text(picked.date, format: .dateTime.day().month(.abbreviated))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(.regularMaterial,
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            PointMark(x: .value("Date", picked.date),
                                      y: .value(metric.rawValue, picked.value))
                                .foregroundStyle(.tint)
                                .symbolSize(90)
                        }
                    }
                    .chartXSelection(value: $scrub)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .frame(height: 240)
                } else {
                    Text("Need at least two sessions of this lift to chart a trend.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(height: 240, alignment: .center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(title: "Short-term", subtitle: "last 3 weeks", change: recent)
            statTile(title: "Long-term", subtitle: "all time", change: allTime)
        }
    }

    private func statTile(title: String, subtitle: String, change: TrendChange?) -> some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.lowercased()).font(.caption).foregroundStyle(.secondary)
                if let c = change {
                    HStack(spacing: 4) {
                        Image(systemName: c.isUp ? "arrow.up.right" : "arrow.down.right")
                        Text(formatted(c.delta) + " \(metric.unit)")
                            .contentTransition(.numericText())
                    }
                    .font(.title3.weight(.bold))
                    .animation(.snappy, value: c.delta)
                    // Accent for up, muted for down. System green/red read as traffic
                    // lights against steel, and red should mean an error, not a dip.
                    .foregroundStyle(c.isUp ? Theme.accent : Color.secondary)
                    Text(String(format: "%+.0f%%", c.percent))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.title3.weight(.bold)).foregroundStyle(.secondary)
                    Text("not enough data").font(.footnote).foregroundStyle(.secondary)
                }
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Dose and response

    /// The lift's weekly best over the last eight weeks, above the weekly sets
    /// its main muscle got, on the same weeks — and one sentence naming the lever.
    private func doseCard(_ dose: DoseResponse) -> some View {
        PanelBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("work and result")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(dose.metric.rawValue.lowercased()) · sets of \(Theme.readableName(dose.exercise)), \(dose.muscle.rawValue) behind")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }

                // Result: the week's best, where the lift was done.
                Chart {
                    ForEach(dose.weeks) { week in
                        if let best = week.best {
                            LineMark(x: .value("Week", week.start), y: .value(dose.metric.rawValue, best))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(.tint)
                            PointMark(x: .value("Week", week.start), y: .value(dose.metric.rawValue, best))
                                .foregroundStyle(.tint)
                                .symbolSize(30)
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 90)

                // Work: this lift's own sets as the bar, every set for its main
                // muscle as a faint bar behind, against the band the total is judged by.
                Chart {
                    RectangleMark(yStart: .value("low", DoseResponse.band.lowerBound),
                                  yEnd: .value("high", DoseResponse.band.upperBound))
                        .foregroundStyle(Theme.accent.opacity(0.12))
                    ForEach(dose.weeks) { week in
                        BarMark(x: .value("Week", week.start), y: .value("Muscle sets", week.sets), width: .ratio(0.6))
                            .foregroundStyle(Color.secondary.opacity(0.22))
                            .cornerRadius(3)
                        BarMark(x: .value("Week", week.start), y: .value("Lift sets", Double(week.liftSets)), width: .ratio(0.6))
                            .foregroundStyle(Theme.accent)
                            .cornerRadius(3)
                    }
                }
                .chartYScale(domain: 0...max(DoseResponse.band.upperBound + 2, (dose.weeks.map(\.sets).max() ?? 0) + 2))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 10, 20]) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 90)

                Text(dose.summary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Weeks

    /// Every day of the last few months as a dot: filled when you trained,
    /// deeper the more sets you did. A missed week is a blank column, visible
    /// without asking anyone.
    private var weeksCard: some View {
        // A Monday with nothing logged yet shows the week just finished.
        let thisWeek = weeks.last
        let showingThisWeek = (thisWeek?.sessions ?? 0) > 0
        let featured = showingThisWeek ? thisWeek : weeks.dropLast().last
        let lastFour = weeks.dropLast().suffix(4)
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
        let weekly = muscleMap.weeklySets(weeks: 5, in: store.sessions)
        let current = weekly.last ?? [:]
        let thisWeekHasSets = current.values.reduce(0, +) > 0
        let shown = thisWeekHasSets ? current : (weekly.dropLast().last ?? [:])
        let previous = Array(weekly.dropLast().suffix(4))
        let groups = MuscleGroup.ordered.filter { g in
            (shown[g] ?? 0) > 0 || previous.contains { ($0[g] ?? 0) > 0 }
        }
        let unmapped = muscleMap.unmapped(in: store.sessions)
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
                        legendSwatch(Theme.accent.opacity(0.14), "10–20 sets a week")
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
        HStack(spacing: 10) {
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
                        .frame(width: max(0, x(20) - x(10)))
                        .offset(x: x(10))
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
            Text(sets == sets.rounded() ? String(Int(sets)) : String(format: "%.1f", sets))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(sets > 0 ? Color.primary : Color.secondary)
                .frame(width: 34, alignment: .trailing)
                .contentTransition(.numericText())
        }
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

    private func formatted(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        let s = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return v >= 0 ? "+\(s)" : s
    }

    private func ensureSelection() {
        // Keep a valid selection; when there isn't one, default to the lift you log
        // most (a better proxy for "the one I care about" than alphabetical order).
        if exercise.isEmpty || !exercises.contains(exercise) { exercise = mostLogged }
        clampMetric()
    }

    /// The exercise appearing in the most sessions (ties broken alphabetically).
    private var mostLogged: String {
        var count: [String: Int] = [:]     // keyed by lowercased name
        var display: [String: String] = [:]
        for name in store.sessions.flatMap({ $0.exercises.map(\.name) }) {
            let key = name.lowercased()
            count[key, default: 0] += 1
            if display[key] == nil { display[key] = name }
        }
        let best = count.max { a, b in
            a.value != b.value ? a.value < b.value : a.key > b.key
        }
        return best.flatMap { display[$0.key] } ?? exercises.first ?? ""
    }

    private func clampMetric() {
        if !availableMetrics.contains(metric) { metric = availableMetrics.first ?? .topSet }
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
                            .font(.system(size: 9, weight: .bold))
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
