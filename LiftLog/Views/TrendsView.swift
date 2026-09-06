import SwiftUI
import Charts

/// Per-lift progression: a chart over time plus short- and long-term change.
/// Generic and lift-focused — no personal goals or targets.
struct TrendsView: View {
    @EnvironmentObject var store: Store

    // Persisted so Trends reopens on the lift you last looked at.
    @AppStorage("trends_exercise") private var exercise = ""
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
                        exercisePicker
                        if availableMetrics.count > 1 { metricPicker }
                        chartCard
                        statsRow
                        weeksCard
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

    // MARK: - Weeks

    /// Every day of the last few months as a dot: filled when you trained,
    /// deeper the more you moved. A missed week is a blank column, visible
    /// without asking anyone.
    private var weeksCard: some View {
        let thisWeek = weeks.last
        let lastFour = weeks.suffix(4)
        let perWeek = lastFour.isEmpty ? 0 : Double(lastFour.map(\.sessions).reduce(0, +)) / Double(lastFour.count)
        let count = thisWeek?.sessions ?? 0

        return PanelBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("training days")
                    .font(.caption).foregroundStyle(.secondary)
                TrainingGrid(weeks: weeks)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("this week").font(.caption2).foregroundStyle(.tertiary)
                        Text(count == 1 ? "1 session" : "\(count) sessions")
                            .font(.subheadline.weight(.bold))
                            .contentTransition(.numericText())
                        Text(kilos(thisWeek?.tonnage ?? 0))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("last 4 weeks").font(.caption2).foregroundStyle(.tertiary)
                        Text(String(format: "%.1f / week", perWeek))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                        Text(kilos(lastFour.map(\.tonnage).reduce(0, +)))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "8 340 kg" — grouped the way the phone's locale groups.
    private func kilos(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " kg"
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
/// Sized to the width it's given — a wider phone simply shows more weeks.
private struct TrainingGrid: View {
    let weeks: [Analytics.TrainingWeek]

    private let dot: CGFloat = 12
    private let gap: CGFloat = 4
    private let labelWidth: CGFloat = 16
    private let rowLabels = ["M", "", "W", "", "F", "", ""]

    var body: some View {
        GeometryReader { geo in
            let fit = Int((geo.size.width - labelWidth + gap) / (dot + gap))
            let shown = Array(weeks.suffix(max(1, fit)))
            let heaviest = shown.flatMap(\.days).compactMap { $0?.tonnage }.max() ?? 0
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
                            cell(week.days[row], heaviest: heaviest, isToday: week.days[row]?.key == today)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 7 * dot + 6 * gap)
    }

    private func cell(_ day: Analytics.TrainingDay?, heaviest: Double, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill(day, heaviest: heaviest))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 1.5)
                }
            }
            .frame(width: dot, height: dot)
    }

    /// Blank for the future, faint for a rest day, accent for a session — the
    /// heavier the day, the deeper the accent. A bodyweight-only day still shows.
    private func fill(_ day: Analytics.TrainingDay?, heaviest: Double) -> Color {
        guard let day else { return .clear }
        guard let tonnage = day.tonnage else { return Color.secondary.opacity(0.14) }
        let intensity = heaviest > 0 ? tonnage / heaviest : 1
        return Theme.accent.opacity(0.4 + 0.6 * intensity)
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
