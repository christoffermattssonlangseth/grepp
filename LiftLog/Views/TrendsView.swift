import SwiftUI
import Charts
import Combine

/// Per-lift progression: a chart over time, short- and long-term change,
/// and, for a lift with a target in goals.md, the day it gets there at this
/// pace.
struct TrendsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    // Persisted so Trends reopens on the lift you last looked at.
    @AppStorage(Prefs.trendsExercise) private var exercise = ""
    /// Two questions, two views: how a lift is going, and how the training
    /// as a whole is going.
    private enum Mode: String, CaseIterable, Identifiable {
        case lift, volume
        var id: String { rawValue }
        var title: String { self == .lift ? "lift" : "volume" }
    }
    @AppStorage(Prefs.trendsMode) private var mode: Mode = .lift
    @AppStorage(Prefs.muscleMap) private var muscleMap = MuscleMap()
    @State private var metric: Analytics.Metric = .topSet
    /// Where a finger is on the chart's x-axis, if it's on it at all.
    @State private var scrub: Date?
    /// How much of the line is drawn: 0 to 1, run on open and on a new lift,
    /// so the trend traces in left to right instead of appearing.
    @State private var drawn: CGFloat = 1
    @State private var weekScrub: Date?
    /// The week under a finger on the work-and-result bars, if any.
    @State private var showingPicker = false
    @State private var settingTarget = false
    /// The left edge of the chart's window when the history is long enough
    /// to scroll; the y-axis follows it.
    @State private var scrollX: Date = .distantPast

    /// Everything the tab draws, computed once per change of the log or the
    /// selection rather than on every body pass: a scrub redraws at touch
    /// rate, and each of these walks the whole log.
    private struct Figures {
        var exercises: [String] = []
        var metrics: [Analytics.Metric] = [.topSet]
        var series: [TrendPoint] = []
        var recent: TrendChange?
        var allTime: TrendChange?
        /// The lift's target from goals.md, and where the trend says it lands.
        var target: Target?
        var projection: Projection?
        var dose: DoseResponse?
        /// The dose card's next session, worked out here once: it walks the
        /// log, and the card asked for it twice a pass.
        var nextStep: DoseResponse.NextStep?
        /// A lift on the lifter's own weight: its targets are reps or added load.
        var bodyweight = false
        /// Every lift read at once, for the list and the dots in the picker.
        var all: [String: DoseResponse] = [:]
        var weeks: [Analytics.TrainingWeek] = []
        var weekly: [MuscleMap.Credits] = []
        /// The same weeks for the balance card, each set once a side.
        var balance: [MuscleMap.Credits] = []
        /// Weeks, counting this one, since the week of the first session
        /// ever: a young log's averages are over the weeks it has.
        var weeksCovered = 0
        var unmapped: [String] = []
        /// The lift's sets measured with BarVelo, oldest first, from velocity.md.
        var speeds: [VelocityRecord] = []
        var speedComparison: VelocityRecord.Comparison?
        var v1rm: VelocityRecord?
        /// Bar velocity against reps in reserve, from the lift's `fail` / `left N`
        /// sets; nil until there are enough of them.
        var reserveModel: ReserveModel?
        /// Reps left at the end of each measured set, own or read off speed.
        var proximity: [VelocityRecord.Proximity] = []
        /// Last-rep speed of each set taken to failure, oldest first.
        var failureSpeeds: [(date: Date, speed: Double)] = []
        var labelledDays = 0
        /// Load against bar velocity over the last twelve weeks, or what it still needs.
        var profileFit: LoadVelocityProfile.Fit = .none
        /// The latest day's first loaded set against the profile without that day.
        var profileReadiness: (record: VelocityRecord, percent: Double)?
    }
    @State private var figures = Figures()
    /// The bar-velocity list past its newest five.
    @State private var showingAllSpeeds = false
    /// Where a finger is on the bar-velocity chart (date, m/s) and on the
    /// reps-left chart (date, reps), if on either. One at a time: a finger on
    /// one clears the other, and the set it picks is highlighted on both.
    @State private var speedScrubX: Date?
    @State private var speedScrubY: Double?
    @State private var reserveScrubX: Date?
    @State private var reserveScrubY: Double?
    /// Where a finger is on the load–velocity chart, kg.
    @State private var profileScrubX: Double?
    /// Reps left at or above this draw at the top of their chart, as 6+.
    private let reserveCap = 6.0

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
                            Text("no data yet")
                        }
                    } description: {
                        Text("A chart appears after a lift's second session; sets per muscle after the first week.")
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
                            if !figures.speeds.isEmpty { speedCard }
                            if figures.profileFit != .none { profileCard }
                            targetCard
                            if let dose = figures.dose {
                                doseCard(dose)
                            }
                            if figures.all.count > 1 { liftsCard }
                        case .volume:
                            weeksCard
                            musclesCard
                            balanceCard
                        }
                    }
                    .padding()
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Theme.backgroundView)
            .navigationTitle("trends")
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
                weekScrub = nil
                showingAllSpeeds = false
                clearVelocityScrub()
                clampMetric()
                recompute()
            }
            .onChange(of: metric) { _, _ in
                scrub = nil
                recompute()
            }
            .onChange(of: muscleMap) { _, _ in recompute() }
            .onChange(of: store.brief.goals) { _, _ in recompute() }
            // A sync, or a measured set written at Finish, changes velocity.md.
            .onChange(of: store.brief.velocity) { _, _ in recompute() }
            .onChange(of: mode) { _, _ in scrub = nil }
            // Every number here is relative to today: coming back after a
            // night, or sitting here past midnight, must not show yesterday's.
            .onChange(of: scenePhase) { _, phase in if phase == .active { recompute() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in recompute() }
            .sheet(isPresented: $settingTarget) {
                TargetSheet(lift: exercise, bodyweight: figures.bodyweight,
                            initial: figures.bodyweight ? (figures.metrics.first == .addedLoad ? .addedLoad : .reps) : .topSet,
                            sessions: store.sessions)
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(history: figures.exercises, library: false,
                                   marks: figures.all.compactMapValues { stateColor($0.state) },
                                   markNames: figures.all.compactMapValues { stateName($0.state) }) { exercise = $0 }
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
            .pill()
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Lift")
        .accessibilityValue(Theme.readableName(exercise))
    }

    private var metricPicker: some View {
        Picker("Metric", selection: $metric) {
            ForEach(figures.metrics) { Text($0.rawValue.lowercased().replacingOccurrences(of: "1rm", with: "1RM")).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Chart

    private var chartCard: some View {
        let series = figures.series
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(metric.rawValue.lowercased()) · \(metric.unit)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let last = series.last?.date {
                        let records = series.filter(\.isRecord).count
                        let tail = records > 0 ? " · \(records) \(records == 1 ? "record" : "records")" : ""
                        Text("last \(last, format: .dateTime.day().month(.abbreviated)) · \(series.count) sessions\(tail)")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }

                if series.count >= 2 {
                    liftChart(series)
                        .frame(height: 240)
                        // The wipe only limits width: the reading under the
                        // finger floats above the plot, outside the chart's
                        // frame, and a frame-sized mask cut it off.
                        .mask(alignment: .leading) {
                            GeometryReader { g in
                                Rectangle()
                                    .frame(width: drawn < 1 ? g.size.width * drawn : g.size.width + 400,
                                           height: g.size.height + 400)
                                    .offset(x: drawn < 1 ? 0 : -200, y: -200)
                            }
                        }
                        .task(id: "\(exercise)|\(metric.rawValue)") {
                            drawn = 0
                            withAnimation(.easeOut(duration: 1.5)) { drawn = 1 }
                        }
                    // The reading under the finger, and the way into that day —
                    // outside the plot, where the chart's own gestures can't eat it.
                    if let picked = scrubbed(in: series) {
                        Button {
                            store.requestEdit(exercise: picked.name.isEmpty ? exercise : picked.name, on: picked.date)
                        } label: {
                            Label("open \(picked.date.formatted(.dateTime.day().month(.abbreviated))) in Log", systemImage: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.panel)
                        .controlSize(.small)
                    } else {
                        Text((scrolls(series) ? "press and drag to read a session · swipe for older ones"
                                              : "drag along the line to read a session")
                             + (series.contains(where: \.isRecord) ? " · green dots are records" : ""))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
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
    /// Longer than one window: two years of sessions were one smear at a
    /// fixed width, and the newest block is what a lifter opens the tab for.
    private func scrolls(_ series: [TrendPoint]) -> Bool {
        guard let first = series.first?.date, let last = series.last?.date else { return false }
        return last.timeIntervalSince(first) > window
    }

    /// The points in the window on screen, for an axis that follows the scroll,
    /// and one either side: the line runs to them off the edge, and an axis
    /// fitted without them lets that segment dive under the dates.
    private func visible(_ series: [TrendPoint]) -> [TrendPoint] {
        guard scrolls(series) else { return series }
        let end = scrollX.addingTimeInterval(window)
        guard let lo = series.firstIndex(where: { $0.date >= scrollX }),
              let hi = series.lastIndex(where: { $0.date <= end }), lo <= hi, hi > lo else { return series }
        return Array(series[max(lo - 1, 0)...min(hi + 1, series.count - 1)])
    }

    @ViewBuilder
    private func liftChart(_ series: [TrendPoint]) -> some View {
        let chart = Chart { liftMarks(series) }
            .chartXSelection(value: $scrub)
            .chartYScale(domain: yDomain(visible(series)))
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

        if scrolls(series), let first = series.first?.date, let last = series.last?.date {
            // Room after the newest point so it isn't pinned to the edge.
            let end = last.addingTimeInterval(window * 0.08)
            chart
                .chartXScale(domain: first...end)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: window)
                .chartScrollPosition(x: $scrollX)
        } else {
            chart
        }
    }

    @ChartContentBuilder
    private func liftMarks(_ series: [TrendPoint]) -> some ChartContent {
        ForEach(series) { point in
            LineMark(x: .value("Date", point.date),
                     y: .value(metric.rawValue, point.value))
                // Straight segments: each point is a session that happened,
                // and nothing between them is drawn as if it were.
                .interpolationMethod(.linear)
                .foregroundStyle(.tint)
            PointMark(x: .value("Date", point.date),
                      y: .value(metric.rawValue, point.value))
                .foregroundStyle(point.isRecord ? Theme.progressing : Theme.accent)
                .symbolSize(point.isRecord ? 64 : 28)
        }
        // Drag along the line to read a session off it.
        if let picked = scrubbed(in: series) {
            RuleMark(x: .value("Date", picked.date))
                .foregroundStyle(.secondary.opacity(0.35))
                .annotation(position: .top, spacing: 6,
                            overflowResolution: .init(x: .fit(to: .plot), y: .disabled)) {
                    reading(picked)
                }
            PointMark(x: .value("Date", picked.date),
                      y: .value(metric.rawValue, picked.value))
                .foregroundStyle(.tint)
                .symbolSize(90)
        }
    }

    /// The session under the finger: the value, the day, the sets as logged.
    /// The way into that day is the button under the chart.
    private func reading(_ picked: TrendPoint) -> some View {
        VStack(spacing: 2) {
            Text("\(WorkSet.formatWeight(picked.value)) \(metric.unit)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
            Text(picked.date, format: .dateTime.day().month(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if picked.isRecord {
                Text("record")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.progressing)
            }
            if !picked.tokens.isEmpty {
                Text(picked.tokens)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Theme.surface,
                    in: RoundedRectangle(cornerRadius: Theme.corner))
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
        let minSpan = metric.unit == "reps" ? 6.0 : max(10, hi * 0.15)
        let half = max(hi - lo, minSpan) / 2 * 1.15
        let mid = (lo + hi) / 2
        let lower = lo >= 0 ? max(0, mid - half) : mid - half
        return lower...max(mid + half, lower + 1)
    }

    private func chartDescription(_ series: [TrendPoint]) -> String {
        guard let first = series.first, let last = series.last else { return metric.rawValue }
        let from = first.date.formatted(.dateTime.day().month(.abbreviated).year())
        let to = last.date.formatted(.dateTime.day().month(.abbreviated).year())
        let records = series.filter(\.isRecord).count
        return "\(metric.rawValue) over \(series.count) sessions from \(from) to \(to), " +
            "from \(WorkSet.formatWeight(first.value)) to \(WorkSet.formatWeight(last.value)) \(metric.unit)" +
            (records > 0 ? ", \(records) \(records == 1 ? "record" : "records")" : "")
    }

    // MARK: - Bar velocity

    /// The lift's sets measured with BarVelo: each a stroke from its last rep
    /// up to its fastest, on the same dates as the chart above; the latest
    /// against the last time at its load; the sets as a list.
    private var speedCard: some View {
        let all = figures.speeds
        let domain = speedDomain(all)
        let shown = all.filter { domain.contains($0.date) }
        let newest = Array(all.reversed())
        let listed = showingAllSpeeds ? newest : Array(newest.prefix(5))
        let reserves = figures.proximity.filter { domain.contains($0.date) }
        let picked = pickedSet(shown, reserves)
        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("bar velocity · m/s").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(all.count) measured \(all.count == 1 ? "set" : "sets")")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                if shown.isEmpty {
                    Text("No measured sets in this stretch of the chart above.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                } else {
                    speedChart(shown, domain: domain, latest: all.last, picked: picked)
                        .frame(height: 140)
                    // The set under the finger, and the way into that day —
                    // outside the plot, as on the lift chart.
                    if let picked, speedScrubX != nil {
                        velocityReading(picked)
                    } else if picked == nil {
                        Text("drag along the chart to read a set")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                if let c = figures.speedComparison {
                    let color = c.isSame ? Color.secondary : (c.isFaster ? Theme.progressing : Theme.stalled)
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(c.sentence { $0.formatted(.dateTime.day().month(.abbreviated)) })
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

                // The profile's own 1RM, on its card, takes over from BarVelo's once there is one.
                if !profileHasOneRepMax, let r = figures.v1rm, let v1rm = r.v1rm {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("velocity 1RM").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(WorkSet.formatWeight(v1rm)) kg")
                            .font(Theme.serif(.title3, weight: .medium))
                            .monospacedDigit()
                        Text(r.date, format: .dateTime.day().month(.abbreviated))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(listed.enumerated()), id: \.offset) { _, r in
                        Text("\(r.date.formatted(.dateTime.day().month(.abbreviated))) · \(r.detail)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if all.count > 5 {
                        Button(showingAllSpeeds ? "show fewer" : "show all \(all.count)") {
                            withAnimation(.snappy) { showingAllSpeeds.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                    }
                }

                Text("MCV is the bar's mean velocity on the way up, rep by rep, from BarVelo: the big dot is the fastest rep, the small one the last. Only measured sets appear.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if figures.reserveModel != nil || figures.proximity.contains(where: \.isOwn) {
                    Divider().padding(.vertical, 2)
                    reserveSection(reserves, domain: domain, picked: picked)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: speedScrubX) { _, x in
            if x != nil { reserveScrubX = nil; reserveScrubY = nil }
        }
        .onChange(of: reserveScrubX) { _, x in
            if x != nil { speedScrubX = nil; speedScrubY = nil }
        }
    }

    private var profileHasOneRepMax: Bool {
        if case .profile(let p) = figures.profileFit { return p.oneRepMax != nil }
        return false
    }

    // MARK: - Load–velocity profile

    /// Load against the fastest rep's speed for every measured set of the last twelve
    /// weeks, the line through them, and what it says: an estimated 1RM where it meets
    /// the threshold, how the latest set compared, and loads for round speeds. Until
    /// there are enough sets, a sentence saying what's missing.
    private var profileCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("load–velocity profile").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("last 12 weeks").font(.caption2).foregroundStyle(.tertiary)
                }
                switch figures.profileFit {
                case .profile(let p):
                    profileContent(p)
                case .needsMore(let why):
                    Text(why).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .none:
                    EmptyView()
                }
                Text("Each dot is a measured set: its load and its fastest rep. Speed falls as load rises; where the line meets the dashed threshold, the speed of a last possible rep, is an estimated 1RM, with no max test.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func profileContent(_ p: LoadVelocityProfile) -> some View {
        profileChart(p).frame(height: 160)
        if let x = profileScrubX {
            let kg = (x / 2.5).rounded() * 2.5
            Text("at \(WorkSet.formatWeight(kg)) kg: \(VelocitySet.speed(max(0, p.speed(at: kg)))) m/s on the profile")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        } else {
            Text("drag along the chart to read a load").font(.caption2).foregroundStyle(.tertiary)
        }
        if let rm = p.oneRepMax, let t = p.threshold {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("estimated 1RM").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(WorkSet.formatWeight((rm / 2.5).rounded() * 2.5)) kg")
                    .font(Theme.serif(.title3, weight: .medium)).monospacedDigit()
                Text("at \(VelocitySet.speed(t)) m/s · \(p.thresholdIsOwn ? "yours" : "typical")")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
        }
        if let (r, d) = figures.profileReadiness, let load = r.load {
            let color = d >= 3 ? Theme.progressing : (d <= -3 ? Theme.stalled : Color.secondary)
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(r.date.formatted(.dateTime.day().month(.abbreviated))), first set at \(WorkSet.formatWeight(load)) kg: \(LoadVelocityProfile.readinessText(d))")
                    .font(.footnote.weight(.semibold)).foregroundStyle(color)
            }
            .accessibilityElement(children: .combine)
        }
        let table = p.loadsForSpeeds
        if !table.isEmpty {
            Text("for a target speed: " + table.map { "\(VelocitySet.speed($0.speed)) m/s ≈ \(WorkSet.formatWeight($0.load)) kg" }.joined(separator: " · "))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func profileChart(_ p: LoadVelocityProfile) -> some View {
        let rm = p.oneRepMax
        let xLo = p.loads.lowerBound * 0.9
        let xHi = max(p.loads.upperBound * 1.05, (rm ?? 0) * 1.03)
        let speeds = p.points.map(\.mcv)
        let yLo = max(0, min(p.threshold ?? speeds.min()!, speeds.min()!) - 0.05)
        let yHi = max(speeds.max()!, p.speed(at: xLo)) + 0.05
        let ends: [(load: Double, speed: Double)] = [(xLo, p.speed(at: xLo)), (xHi, p.speed(at: xHi))]
        let newest = p.points.map(\.date).max() ?? Date()
        return Chart {
            ForEach(Array(ends.enumerated()), id: \.offset) { _, e in
                LineMark(x: .value("Load", e.load), y: .value("m/s", e.speed))
                    .foregroundStyle(Theme.accent.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let t = p.threshold {
                RuleMark(y: .value("Threshold", t))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if let rm {
                    PointMark(x: .value("Load", rm), y: .value("m/s", t))
                        .symbol(.diamond)
                        .foregroundStyle(Theme.accent)
                        .symbolSize(60)
                        .annotation(position: .top, spacing: 3) {
                            Text("1RM").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            ForEach(Array(p.points.enumerated()), id: \.offset) { _, pt in
                // Newer sets darker: the last twelve weeks fade from light to full.
                let age = newest.timeIntervalSince(pt.date) / LoadVelocityProfile.window
                PointMark(x: .value("Load", pt.load), y: .value("m/s", pt.mcv))
                    .foregroundStyle(Theme.accent.opacity(1 - 0.6 * min(1, max(0, age))))
                    .symbolSize(36)
            }
            if let x = profileScrubX {
                RuleMark(x: .value("Load", x)).foregroundStyle(.secondary.opacity(0.35))
            }
        }
        .chartXScale(domain: xLo...xHi)
        .chartYScale(domain: yLo...yHi)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                AxisValueLabel { if let kg = v.as(Double.self) { Text("\(Int(kg)) kg") } }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2)))
            }
        }
        .chartXSelection(value: $profileScrubX)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("load–velocity profile of \(p.points.count) measured sets")
        .accessibilityValue(p.summary(lift: exercise))
    }

    private func clearVelocityScrub() {
        speedScrubX = nil; speedScrubY = nil
        reserveScrubX = nil; reserveScrubY = nil
    }

    /// The measured set under the finger, on whichever chart it's on: the
    /// nearest day with a set, then of that day's sets the one nearest the
    /// finger's height — a drag snaps to sets that were lifted.
    private func pickedSet(_ shown: [VelocityRecord], _ reserves: [VelocityRecord.Proximity]) -> VelocityRecord? {
        if let x = speedScrubX {
            let y = speedScrubY
            return Self.nearest(shown, to: x, date: { $0.date }) { r in
                y.map { min(abs(r.best - $0), abs(r.lastRep - $0)) } ?? 0
            }
        }
        if let x = reserveScrubX {
            let y = reserveScrubY
            let cap = reserveCap
            return Self.nearest(reserves, to: x, date: { $0.date }) { p in
                y.map { abs(min(p.reserve, cap) - $0) } ?? 0
            }?.record
        }
        return nil
    }

    private static func nearest<T>(_ items: [T], to x: Date, date: (T) -> Date, distance: (T) -> Double) -> T? {
        guard let day = items.map(date).min(by: { abs($0.timeIntervalSince(x)) < abs($1.timeIntervalSince(x)) })
        else { return nil }
        return items.filter { date($0) == day }.min { distance($0) < distance($1) }
    }

    /// One measured set in a line: `6 Oct · set 3 · 110×12 · 0.42 → 0.32 m/s
    /// · −24% · RPE 9 · 1 left (yours)`. Reps left come from the lifter's
    /// answer, else the fit's reading of the last rep; a failed set has none
    /// to add.
    private func velocityReadingText(_ r: VelocityRecord) -> String {
        var parts = [r.date.formatted(.dateTime.day().month(.abbreviated)), r.detail]
        if r.left != .failed, let p = figures.proximity.first(where: { $0.record == r }) {
            parts.append(p.isOwn ? "\(Int(p.reserve)) left (yours)"
                                 : "≈\(VelocitySet.tenth((p.reserve * 2).rounded() / 2)) left (est.)")
        }
        return parts.joined(separator: " · ")
    }

    /// The picked set's reading, as a button into that day in Log.
    private func velocityReading(_ r: VelocityRecord) -> some View {
        let text = velocityReadingText(r)
        // The lift as the log spelled it that day, when the chart above has it.
        let name = figures.series.first { Calendar.current.isDate($0.date, inSameDayAs: r.date) }?.name ?? ""
        return Button {
            store.requestEdit(exercise: name.isEmpty ? r.lift : name, on: r.date)
        } label: {
            Label(text, systemImage: "arrow.up.right")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.panel)
        .controlSize(.small)
        .accessibilityLabel("open \(r.date.formatted(.dateTime.day().month(.wide))) in Log")
        .accessibilityValue(text)
    }

    /// VoiceOver's way along a chart: swipe up or down for the next or
    /// previous set, the way a finger drags.
    private func step<T>(_ items: [T], from current: Int?, _ direction: AccessibilityAdjustmentDirection) -> T? {
        guard !items.isEmpty else { return nil }
        switch direction {
        case .increment: return items[current.map { min($0 + 1, items.count - 1) } ?? items.count - 1]
        case .decrement: return items[current.map { max($0 - 1, 0) } ?? items.count - 1]
        @unknown default: return nil
        }
    }

    /// How close each measured set ended to failure, the lifter's own answer
    /// or the speed's reading of it; what the speed says about failure; and,
    /// once there are answers on two days, the failure velocity over time.
    @ViewBuilder
    private func reserveSection(_ shown: [VelocityRecord.Proximity], domain: ClosedRange<Date>, picked: VelocityRecord?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("reps left at the end of the set").font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 8) {
                Label { Text("yours") } icon: { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
                Label { Text("from velocity") } icon: { Circle().strokeBorder(Theme.accent, lineWidth: 1.5).frame(width: 7, height: 7) }
            }
            .labelStyle(CompactLegend())
            .font(.caption2).foregroundStyle(.tertiary)
        }

        if shown.isEmpty {
            Text("No sets with reps left in this stretch of the chart above.")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
        } else {
            reserveChart(shown, domain: domain, picked: picked)
                .frame(height: 110)
            if let picked, reserveScrubX != nil {
                velocityReading(picked)
            }
        }

        if let m = figures.reserveModel {
            Text(m.summary(lift: Theme.readableName(exercise)))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Text(m.lookup.map { "\(VelocitySet.speed($0.speed)) m/s → \($0.reserve) left" }.joined(separator: " · "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text("Not enough answered sets to read reps left from velocity yet: it takes four reps within five of failure.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if figures.labelledDays >= 2, figures.failureSpeeds.count >= 2 {
            HStack(alignment: .center, spacing: 8) {
                Text("failure velocity").font(.caption).foregroundStyle(.secondary)
                failureSparkline(figures.failureSpeeds)
                    .frame(height: 28)
                if let last = figures.failureSpeeds.last {
                    Text("\(VelocitySet.speed(last.speed)) m/s")
                        .font(.caption.monospacedDigit())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("failure velocity over \(figures.failureSpeeds.count) sets taken to failure")
            .accessibilityValue(figures.failureSpeeds.map { VelocitySet.speed($0.speed) }.joined(separator: ", ") + " m/s")
        }

        Text("Estimates assume the same filming setup. Answer “reps left?” in BarVelo, or mark failed sets, to sharpen them.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Reps left, 0 to 6+, on the same dates as the speed chart: filled for
    /// the lifter's answer, hollow for the speed's reading.
    private func reserveChart(_ shown: [VelocityRecord.Proximity], domain: ClosedRange<Date>,
                              picked: VelocityRecord?) -> some View {
        let cap = reserveCap
        return Chart {
            if let picked {
                RuleMark(x: .value("Date", picked.date))
                    .foregroundStyle(.secondary.opacity(0.35))
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, p in
                let isPicked = p.record == picked
                let size: CGFloat = isPicked ? 12 : 8
                PointMark(x: .value("Date", p.date), y: .value("Reps left", min(p.reserve, cap)))
                    .symbol {
                        if p.isOwn {
                            Circle().fill(Theme.accent).frame(width: size, height: size)
                        } else {
                            Circle().strokeBorder(Theme.accent, lineWidth: isPicked ? 2 : 1.5).frame(width: size, height: size)
                        }
                    }
                    .opacity(picked == nil || isPicked ? 1 : 0.5)
            }
        }
        .chartXSelection(value: $reserveScrubX)
        .chartYSelection(value: $reserveScrubY)
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...cap)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 2, 4, 6]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(v >= cap ? "6+" : "\(Int(v))") }
                }
            }
        }
        .chartYAxisLabel("reps left")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("reps left at the end of \(shown.count) measured \(shown.count == 1 ? "set" : "sets")")
        .accessibilityValue(picked.map { velocityReadingText($0) } ?? shown.last.map {
            "latest \(VelocitySet.tenth(($0.reserve * 2).rounded() / 2)) \($0.isOwn ? "by your answer" : "from velocity")"
        } ?? "")
        .accessibilityHint("swipe up or down to read a set")
        .accessibilityAdjustableAction { direction in
            let current = picked.flatMap { r in shown.firstIndex { $0.record == r } }
            guard let p = step(shown, from: current, direction) else { return }
            reserveScrubX = p.date
            reserveScrubY = min(p.reserve, cap)
        }
    }

    /// The failure velocity of each set taken to failure, as a line.
    private func failureSparkline(_ points: [(date: Date, speed: Double)]) -> some View {
        let lo = points.map(\.speed).min() ?? 0
        let hi = points.map(\.speed).max() ?? 1
        let pad = max(hi - lo, 0.04) / 2
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Date", p.date), y: .value("Failure velocity", p.speed))
                    .foregroundStyle(Theme.accent.opacity(0.6))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", p.date), y: .value("Failure velocity", p.speed))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(14)
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func speedChart(_ shown: [VelocityRecord], domain: ClosedRange<Date>, latest: VelocityRecord?,
                            picked: VelocityRecord?) -> some View {
        let lo = shown.map(\.lastRep).min() ?? 0
        let hi = shown.map(\.best).max() ?? 1
        let half = max(hi - lo, 0.2) / 2 * 1.2
        let mid = (lo + hi) / 2
        let lower = max(0, mid - half)
        return Chart {
            // Drag along the strokes to read a set off them.
            if let picked {
                RuleMark(x: .value("Date", picked.date))
                    .foregroundStyle(.secondary.opacity(0.35))
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, r in
                let isPicked = r == picked
                let faded = picked != nil && !isPicked
                RuleMark(x: .value("Date", r.date),
                         yStart: .value("Last rep", r.lastRep),
                         yEnd: .value("Fastest rep", r.best))
                    .lineStyle(StrokeStyle(lineWidth: isPicked ? 2.5 : 1.5, lineCap: .round))
                    .foregroundStyle(Theme.accent.opacity(isPicked ? 0.8 : 0.4))
                    .opacity(faded ? 0.5 : 1)
                PointMark(x: .value("Date", r.date), y: .value("Last rep", r.lastRep))
                    .foregroundStyle(Theme.accent.opacity(0.6))
                    .symbolSize(isPicked ? 28 : 12)
                    .opacity(faded ? 0.5 : 1)
                let isLatest = r == latest && picked == nil
                PointMark(x: .value("Date", r.date), y: .value("Fastest rep", r.best))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(isPicked ? 90 : 36)
                    .opacity(faded ? 0.5 : 1)
                    .annotation(position: .top, spacing: 3,
                                overflowResolution: .init(x: .fit(to: .plot), y: .disabled)) {
                        if isLatest {
                            Text(r.loadLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: lower...(mid + half))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2)))
            }
        }
        .chartXSelection(value: $speedScrubX)
        .chartYSelection(value: $speedScrubY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("bar velocity of \(shown.count) measured \(shown.count == 1 ? "set" : "sets")")
        .accessibilityValue(picked.map { velocityReadingText($0) } ?? shown.last.map { "latest \($0.detail)" } ?? "")
        .accessibilityHint("swipe up or down to read a set")
        .accessibilityAdjustableAction { direction in
            guard let r = step(shown, from: picked.flatMap { shown.firstIndex(of: $0) }, direction) else { return }
            speedScrubX = r.date
            speedScrubY = r.best
        }
    }

    /// The dates the bar-velocity chart spans: the window the chart above shows
    /// when it scrolls, its whole span when it doesn't, so a day sits under
    /// itself; widened to the measured sets when the lift chart has none.
    private func speedDomain(_ records: [VelocityRecord]) -> ClosedRange<Date> {
        let series = figures.series
        if scrolls(series) {
            return scrollX...scrollX.addingTimeInterval(window)
        }
        let dates = records.map(\.date) + (series.count >= 2 ? series.map(\.date) : [])
        let first = dates.min() ?? Date()
        let last = dates.max() ?? Date()
        // One day alone, or two close together, still gets some width.
        let pad = max(0, 6 * 86_400 - last.timeIntervalSince(first)) / 2
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    // MARK: - Target

    /// The target for this lift out of goals.md and the day the trend says
    /// it lands: green when that is before the date asked for, or there is
    /// none; amber when the pace is flat or the date has slipped past. With
    /// no target, one button to set one, which writes a line to goals.md.
    private var targetCard: some View {
        Panel {
            if let target = figures.target {
                let wanted = target.amount
                let color = targetColor(target, figures.projection)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("target · \(target.kind.label)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let by = target.by {
                            Text("by \(by, format: .dateTime.day().month(.abbreviated).year())")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(wanted).font(.title3.weight(.bold)).foregroundStyle(color)
                        if let p = figures.projection {
                            Text("· now \(target.isReps ? String(Int(p.current)) : WorkSet.formatWeight(p.current))")
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Text(targetLine(target, figures.projection))
                        .font(.footnote).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("from goals.md").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("target").font(.caption).foregroundStyle(.secondary)
                        Text("A number to hit, and the day this pace gets there.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Set a target") { settingTarget = true }
                        .buttonStyle(.panel)
                        .controlSize(.small)
                        .disabled(exercise.isEmpty)
                }
            }
        }
    }

    private func targetColor(_ target: Target, _ p: Projection?) -> Color {
        guard let p else { return Color.secondary }
        if p.isMet { return Theme.progressing }
        guard let date = p.date else { return Theme.stalled }
        if let by = target.by, date > by { return Theme.stalled }
        return Theme.progressing
    }

    /// "At this pace, around 14 Nov." / "Met." / "No pace yet: flat over the
    /// last twelve weeks." / "…14 Nov, past the date asked for."
    private func targetLine(_ target: Target, _ p: Projection?) -> String {
        guard let p else { return "Two sessions of this lift are needed to read a pace." }
        if p.isMet { return "Met. The log has reached it." }
        guard let date = p.date, let perDay = p.perDay else {
            return "No pace yet: flat, falling or not lifted over the last twelve weeks."
        }
        let unit = target.kind.unit
        let weekly = perDay * 7
        let pace = String(format: weekly >= 1 ? "%.0f" : "%.1f", weekly) + " \(unit) a week"
        let when = date.formatted(.dateTime.day().month(.abbreviated).year())
        if let by = target.by, date > by {
            return "At this pace, \(pace), around \(when) — past the date asked for."
        }
        return "At this pace, \(pace), around \(when)."
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
        statTile(title: "short-term", subtitle: "last 3 weeks", change: figures.recent,
                 empty: "no two sessions in the window")
        statTile(title: "long-term", subtitle: "all time", change: figures.allTime,
                 empty: "not enough data")
    }

    private func statTile(title: String, subtitle: String, change: TrendChange?, empty: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let c = change {
                    HStack(spacing: 4) {
                        Image(systemName: c.isUp ? "arrow.up.right" : (c.isFlat ? "arrow.right" : "arrow.down.right"))
                        Text(formatted(c.delta) + " \(metric.unit)")
                            .contentTransition(.numericText())
                    }
                    .font(.title3.weight(.bold))
                    .animation(.snappy, value: c.delta)
                    // Green for up, muted for down: a dip is not an error.
                    .foregroundStyle(c.isUp ? Theme.progressing : Color.secondary)
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
        // Headroom for the count printed over each bar.
        let tallest = dose.weeks.map { Double($0.liftSets) }.max() ?? 0
        let top = max(6, tallest + 3)
        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("work and result")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("sets a week, last \(dose.weeks.count) weeks")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                // Work: this lift's own sets a week. The muscle's total is in
                // the sentence and the tap read-out, not drawn: a second bar
                // behind the first read as an outline. The 10–20 band is a
                // muscle's number, not a lift's: it is on the Volume tab.
                // Each bar spans the middle of its own Monday-to-Sunday week,
                // from the dates themselves: Charts' .weekOfYear bins start on
                // the locale's first weekday — Sunday in the US — so a bar
                // straddled two of the model's weeks and a tap on its left
                // edge picked the week before.
                Chart {
                    ForEach(dose.weeks) { week in
                        let bar = weekBar(week.start)
                        BarMark(xStart: .value("Week", bar.start),
                                xEnd: .value("Week", bar.end),
                                y: .value("Lift sets", Double(week.liftSets)))
                            .foregroundStyle(Theme.accent)
                            .cornerRadius(3)
                            .opacity(pickedWeek == nil || pickedWeek?.start == week.start ? 1 : 0.5)
                        // The count over its bar: its own mark, drawn after
                        // the bar and never dropped for being near the top;
                        // the domain leaves room for it.
                        if week.liftSets > 0 {
                            PointMark(x: .value("Week", bar.mid),
                                      y: .value("Top", Double(week.liftSets)))
                                .symbolSize(0)
                                .annotation(position: .top, spacing: 2,
                                            overflowResolution: .init(x: .fit(to: .plot), y: .disabled)) {
                                    Text("\(week.liftSets)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                }
                .chartYScale(domain: 0...top)
                // The weeks end to end, a little air at both ends so the first
                // and last bars don't touch the frame.
                .chartXScale(domain: weeksDomain(dose.weeks), range: .plotDimension(padding: 6))
                // Every other week, labelled with its Monday under its bar.
                .chartXAxis {
                    AxisMarks(values: weekLabels(dose.weeks)) { value in
                        if let mid = value.as(Date.self) {
                            AxisValueLabel {
                                Text(weekSpan(mid).start, format: .dateTime.day().month(.abbreviated))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 110)
                .accessibilityLabel("\(lift) sets a week, last \(dose.weeks.count) weeks")
                .accessibilityValue(dose.summary)
                // A tap on a week picks it and reads it out in one line.
                .chartXSelection(value: $weekScrub)

                if let week = pickedWeek {
                    Text(weekLine(week, dose: dose))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                // The verdict as a colour first, then as the sentence.
                if let color = stateColor(dose.state), let name = stateName(dose.state) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color)
                    }
                    .accessibilityElement(children: .combine)
                }

                Text(dose.summary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if dose.verdict != .tooEarly {
                    // The advice as a session: the last one with the one
                    // change the verdict asks for, straight into the Log.
                    HStack(spacing: 8) {
                        if let step = figures.nextStep {
                            Button {
                                store.requestLog([step.entry])
                            } label: {
                                Label("Load next step: \(step.label)", systemImage: "arrow.down.to.line")
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .buttonStyle(.panelProminent)
                            .controlSize(.small)
                            .tint(Theme.accent)
                            .accessibilityHint(step.entry.sets.map(\.token).joined(separator: " "))
                        }
                        Button {
                            store.requestCoach(dose.coachQuestion())
                        } label: {
                            Label("Ask the coach", systemImage: "bubble.left.and.text.bubble.right")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.panel)
                        .controlSize(.small)
                    }
                    if let step = figures.nextStep {
                        Text("next: " + step.entry.sets.map(\.token).joined(separator: "  "))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Every lift

    /// One line per lift with something to say: its dot, its name, what it
    /// moved by or how long it has stood. Stalled first, since those are
    /// the ones to do something about; a tap makes it the lift shown.
    private var liftsCard: some View {
        let rows = figures.all.values.sorted { a, b in
            if a.state != b.state { return a.state == .stalled }
            return a.exercise < b.exercise
        }
        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("your lifts").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("last 8 weeks").font(.caption2).foregroundStyle(.tertiary)
                }
                ForEach(rows, id: \.exercise) { dose in
                    let current = dose.exercise == exercise
                    Button {
                        exercise = dose.exercise
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(stateColor(dose.state) ?? Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                            Text(Theme.readableName(dose.exercise))
                                .font(.subheadline.weight(current ? .semibold : .regular))
                                .lineLimit(1)
                            Spacer()
                            Text(dose.short)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(stateColor(dose.state) ?? Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Theme.readableName(dose.exercise)), \(stateName(dose.state) ?? "too early"), \(dose.short)")
                    .accessibilityAddTraits(current ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Green for a lift going up, amber for one that has stopped; nothing
    /// for one too young to say — no colour is the honest colour there.
    private func stateColor(_ state: DoseResponse.State) -> Color? {
        switch state {
        case .progressing: return Theme.progressing
        case .stalled: return Theme.stalled
        case .tooEarly: return nil
        }
    }

    private func stateName(_ state: DoseResponse.State) -> String? {
        switch state {
        case .progressing: return "progressing"
        case .stalled: return "stalled"
        case .tooEarly: return nil
        }
    }

    /// The week the finger is on, from the dose card's own weeks, by the
    /// calendar: a week across a clock change is not 7 × 86,400 seconds.
    private var pickedWeek: DoseResponse.Week? {
        guard let weekScrub, let dose = figures.dose else { return nil }
        return dose.weeks.first { week in
            let span = weekSpan(week.start)
            return weekScrub >= span.start && weekScrub < span.end
        }
    }

    /// Monday to the next Monday — the model's week, whatever the locale
    /// calls the first day. Any date in a week gives that week.
    private func weekSpan(_ date: Date) -> DateInterval {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        // Calendar weekdays run Sunday = 1 … Saturday = 7; a gym week starts Monday.
        let back = (calendar.component(.weekday, from: day) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -back, to: day) ?? day
        let next = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday.addingTimeInterval(7 * 86_400)
        return DateInterval(start: monday, end: next)
    }

    /// A bar over the middle six tenths of its week, and the middle for the
    /// count over it.
    private func weekBar(_ start: Date) -> (start: Date, end: Date, mid: Date) {
        let span = weekSpan(start)
        return (span.start.addingTimeInterval(span.duration * 0.2),
                span.start.addingTimeInterval(span.duration * 0.8),
                span.start.addingTimeInterval(span.duration * 0.5))
    }

    private func weeksDomain(_ weeks: [DoseResponse.Week]) -> ClosedRange<Date> {
        guard let first = weeks.first, let last = weeks.last else { return Date()...Date() }
        return weekSpan(first.start).start...weekSpan(last.start).end
    }

    /// The middle of every other week, newest included, for the axis labels.
    private func weekLabels(_ weeks: [DoseResponse.Week]) -> [Date] {
        weeks.reversed().enumerated().filter { $0.offset % 2 == 0 }.map { item in
            let span = weekSpan(item.element.start)
            return span.start.addingTimeInterval(span.duration / 2)
        }
    }

    /// "week of 8 Sep · 9 bench press sets · 14 chest in all · best 100 kg"
    private func weekLine(_ week: DoseResponse.Week, dose: DoseResponse) -> String {
        let lift = Theme.readableName(dose.exercise)
        let all = week.sets == week.sets.rounded() ? String(Int(week.sets)) : String(format: "%.1f", week.sets)
        var line = "week of " + week.start.formatted(.dateTime.day().month(.abbreviated))
        line += week.liftSets == 0 ? " · no \(lift)" : " · \(week.liftSets) \(lift) sets"
        line += " · \(all) \(dose.muscle.rawValue) in all"
        if let best = week.best { line += " · best \(WorkSet.formatWeight(best)) \(dose.metric.unit)" }
        return line
    }

    // MARK: - Weeks

    /// Every day of the last few months as a dot: filled when you trained,
    /// deeper the more sets you did. A missed week is a blank column, visible
    /// without asking anyone.
    private var weeksCard: some View {
        let weeks = figures.weeks
        // A Monday with nothing logged yet shows the week just finished — and
        // compares it with the four before it, not with itself.
        let pick = weekToShow(weeks)
        let showingThisWeek = pick.isThisWeek
        let featured = pick.shown
        let lastFour = pick.previous
        let perWeek = lastFour.isEmpty ? 0 : Double(lastFour.map(\.sessions).reduce(0, +)) / Double(lastFour.count)
        let setsPerWeek = lastFour.isEmpty ? 0 : Double(lastFour.map(\.sets).reduce(0, +)) / Double(lastFour.count)
        let count = featured?.sessions ?? 0
        // Showing up as planned: the programme's days a week when there is
        // one, else two. The grid is 26 weeks long, so a run that fills it
        // reads as 26 or more.
        let minimum = max(1, min(7, store.programme.days.isEmpty ? 2 : store.programme.days.count))
        let streak = Analytics.streak(weeks, minimum: minimum)

        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("training days")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if streak > 0 {
                        Text("\(streak == weeks.count ? "\(streak)+" : "\(streak)") \(streak == 1 ? "week" : "weeks") in a row · \(minimum)+ a week")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(streak >= 4 ? Theme.progressing : Color.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
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
                        Text(previousLabel(lastFour.count)).font(.caption2).foregroundStyle(.tertiary)
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
        let pick = weekToShow(weekly)
        let thisWeekHasSets = pick.isThisWeek
        let shown = pick.shown ?? [:]
        let previous = pick.previous
        let groups = MuscleGroup.ordered.filter { g in
            (shown[g] ?? 0) > 0 || previous.contains { ($0[g] ?? 0) > 0 }
        }
        let unmapped = figures.unmapped
        let scale = max(20, groups.map { shown[$0] ?? 0 }.max() ?? 0,
                        groups.map { avg($0, in: previous) }.max() ?? 0)

        return Panel {
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
                        legendSwatch(Color.primary.opacity(0.55), "\(max(1, previous.count))-week average", thin: true)
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

    // MARK: - Balance

    /// Push against pull, quads against hamstrings, as sets a week over the
    /// four weeks before the one shown. A split bar and a verdict: even, or
    /// which side is short.
    private var balanceCard: some View {
        let pick = weekToShow(figures.balance)
        let pairs = Balance.pairs(over: pick.previous)
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("balance").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(previousLabel(pick.previous.count) + ", sets a week").font(.caption2).foregroundStyle(.tertiary)
                }
                if pairs.isEmpty {
                    Text("A few weeks of sets per muscle first.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(pairs) { pair in
                        let short = pair.short
                        let readable = pair.a.sets + pair.b.sets >= Balance.Pair.minimum
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(pair.a.name) \(String(format: "%.0f", pair.a.sets))")
                                    .font(.caption.weight(.semibold)).monospacedDigit()
                                Spacer()
                                Text(pair.verdict)
                                    .font(.caption)
                                    .foregroundStyle(!readable ? Color.secondary : (short == nil ? Theme.progressing : Theme.stalled))
                                Spacer()
                                Text("\(String(format: "%.0f", pair.b.sets)) \(pair.b.name)")
                                    .font(.caption.weight(.semibold)).monospacedDigit()
                            }
                            GeometryReader { geo in
                                let total = max(1, pair.a.sets + pair.b.sets)
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(short?.name == pair.a.name ? Theme.stalled : Theme.accent)
                                        .frame(width: max(2, geo.size.width * pair.a.sets / total - 1))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(short?.name == pair.b.name ? Theme.stalled : Color.secondary.opacity(0.35))
                                }
                            }
                            .frame(height: 8)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(pair.a.name) \(String(format: "%.0f", pair.a.sets)) sets a week, \(pair.b.name) \(String(format: "%.0f", pair.b.sets)), \(pair.verdict)")
                    }
                    Text("Even means the smaller side has at least seven tenths of the larger.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// This week once a session is logged in it, else last week — and up to
    /// four weeks before whichever is shown, never including it, nor any week
    /// before the first session: a three-week-old log is averaged over what
    /// it has, not over four. All three Volume cards make this choice, and
    /// they have to make it the same way, so it is made from the training
    /// days for all of them: a week of only unassigned lifts is still this
    /// week. `weeks` ends on this week, like every array the cards draw.
    private func weekToShow<T>(_ weeks: [T]) -> (shown: T?, previous: [T], isThisWeek: Bool) {
        guard let last = weeks.last else { return (nil, [], true) }
        let thisWeek = (figures.weeks.last?.sessions ?? 0) > 0
        let shown = thisWeek ? last : weeks.dropLast().last
        let covered = weeks.suffix(figures.weeksCovered)
        let prior = thisWeek ? covered.dropLast() : covered.dropLast(2)
        return (shown, Array(prior.suffix(4)), thisWeek)
    }

    /// "previous 4 weeks", or as many as a young log has.
    private func previousLabel(_ count: Int) -> String {
        count <= 1 ? "previous week" : "previous \(count) weeks"
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
        var counts: [String: Int] = [:]
        for session in store.sessions {
            for key in Set(session.exercises.map { MuscleMap.canonical($0.name) }) { counts[key, default: 0] += 1 }
        }
        let best = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }
        return best.flatMap { top in names.first { MuscleMap.canonical($0) == top.key } } ?? names.first ?? ""
    }

    private func clampMetric() {
        let metrics = Analytics.availableMetrics(exercise, in: store.sessions)
        if !metrics.contains(metric) { metric = metrics.first ?? .topSet }
    }

    private func recompute() {
        var f = Figures()
        f.exercises = knownLifts()
        f.weeks = Analytics.weekGrid(weeks: 26, in: store.sessions)
        // Day keys sort as dates; a first session before the grid covers it all.
        if let first = store.sessions.map(\.dateString).min() {
            let start = f.weeks.firstIndex { $0.days.contains { ($0?.key ?? "") >= first } } ?? f.weeks.count
            f.weeksCovered = f.weeks.count - start
        }
        f.weekly = muscleMap.weeklySets(weeks: 6, in: store.sessions)
        f.balance = Balance.weeklySets(weeks: 6, in: store.sessions, map: muscleMap)
        f.unmapped = muscleMap.unmapped(in: store.sessions)
        f.all = DoseResponse.all(for: f.exercises, in: store.sessions, map: muscleMap)
        if !exercise.isEmpty {
            f.metrics = Analytics.availableMetrics(exercise, in: store.sessions)
            let shown = f.metrics.contains(metric) ? metric : (f.metrics.first ?? .topSet)
            f.series = Analytics.series(exercise, metric: shown, in: store.sessions)
            // A new span starts at its newest block; the same span keeps its place.
            if f.series.first?.date != figures.series.first?.date || f.series.last?.date != figures.series.last?.date,
               let last = f.series.last?.date {
                scrollX = last.addingTimeInterval(window * 0.08 - window)
            }
            f.recent = Analytics.change(f.series, sinceDays: 21)
            f.allTime = Analytics.change(f.series)
            // The target is judged on its own number — top set, estimated
            // 1RM, added load or reps — whatever metric the chart is showing.
            f.bodyweight = Analytics.isBodyweight(exercise, in: store.sessions)
            if let target = Targets.target(for: exercise, in: store.targets, sessions: store.sessions) {
                f.target = target
                let line = Analytics.series(exercise, metric: target.kind.metric, in: store.sessions)
                f.projection = Analytics.projection(line, to: target.value)
            }
            // Already read with every other lift; reading it again walked the log twice.
            f.dose = f.all[exercise] ?? f.all.first { Analytics.matches($0.key, exercise) }?.value
            f.nextStep = f.dose?.nextStep(in: store.sessions)
            f.speeds = VelocityRecord.records(for: exercise, in: VelocityRecord.parse(store.brief.velocity))
            f.speedComparison = VelocityRecord.sameLoadComparison(f.speeds)
            f.v1rm = VelocityRecord.latestV1RM(f.speeds)
            f.reserveModel = ReserveModel.fit(f.speeds)
            f.proximity = VelocityRecord.proximity(f.speeds, model: f.reserveModel)
            f.failureSpeeds = VelocityRecord.failureSpeeds(f.speeds)
            f.labelledDays = VelocityRecord.labelledDays(f.speeds)
            f.profileFit = LoadVelocityProfile.fit(f.speeds, lift: exercise)
            f.profileReadiness = LoadVelocityProfile.readiness(f.speeds, lift: exercise)
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

/// A number to hit for the lift shown, and the day it's wanted by, written
/// to goals.md as one line the coach and Trends both read.
private struct TargetSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let lift: String
    /// A bodyweight lift is offered reps and added load; a weighted one, a
    /// top set and an estimated max.
    let bodyweight: Bool
    /// The kind picked when the sheet opens.
    let initial: Target.Kind
    let sessions: [Session]

    @State private var kind: Target.Kind = .topSet
    @State private var valueText = ""
    @State private var hasDate = false
    @State private var by = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var saving = false
    @State private var failed = false

    private var value: Double? { Double(valueText.replacingOccurrences(of: ",", with: ".")) }
    private var isReps: Bool { kind == .reps }
    /// Where the lift stands on the number the target is of.
    private var current: Double? { Analytics.series(lift, metric: kind.metric, in: sessions).last?.value }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Number", selection: $kind) {
                        if bodyweight {
                            Text("reps").tag(Target.Kind.reps)
                            Text("added load").tag(Target.Kind.addedLoad)
                        } else {
                            Text("top set").tag(Target.Kind.topSet)
                            Text("est. 1RM").tag(Target.Kind.oneRepMax)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        TextField(isReps ? "reps" : "kg", text: $valueText)
                            .keyboardType(isReps ? .numberPad : .decimalPad)
                            .font(.title2.weight(.bold))
                        Text(isReps ? "reps" : "kg").foregroundStyle(.secondary)
                    }
                } header: {
                    Text(Theme.readableName(lift))
                } footer: {
                    if let current {
                        Text("Now \(isReps ? String(Int(current)) : WorkSet.formatWeight(current)) \(kind.unit), \(kind.label).")
                    }
                }
                .listRowBackground(Theme.row)
                .onAppear { kind = initial }
                Section {
                    Toggle("By a date", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Date", selection: $by, in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    Text("Written as one line to goals.md, beside whatever is there.")
                }
                .listRowBackground(Theme.row)
                if failed {
                    Text("Couldn't save goals.md. Check the connection and try again.")
                        .font(.footnote).foregroundStyle(Theme.warning)
                        .listRowBackground(Theme.row)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundView)
            .navigationTitle("set a target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(value == nil || (value ?? 0) <= 0 || saving)
                }
            }
        }
    }

    private func save() async {
        guard let value else { return }
        saving = true
        failed = false
        let line = Targets.line(lift: MuscleMap.canonical(lift), value: value, kind: kind, by: hasDate ? by : nil)
        let result = await store.addTarget(line)
        saving = false
        if result == .pushed { dismiss() } else { failed = true }
    }
}

/// A legend entry: a small mark, then its word, tight.
private struct CompactLegend: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
