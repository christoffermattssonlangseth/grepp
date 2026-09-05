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
