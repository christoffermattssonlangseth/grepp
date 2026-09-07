import Foundation

/// Is the work producing the result? One lift's progression set beside the
/// weekly sets its main muscle got, over the last weeks, and a verdict.
///
/// Read as a block, not week by week: this week's sets show up in the top set
/// two or three weeks later, and a young log is noisy. The verdict is the part
/// that turns two numbers into a lever: flat at low volume means add sets;
/// flat at high volume means volume isn't the lever.
struct DoseResponse: Equatable {
    struct Week: Equatable, Identifiable {
        var id: Date { start }
        let start: Date
        /// Weekly sets for the lift's main muscle, credits included.
        let sets: Double
        /// The week's best for the lift's own metric (top set, reps…); nil when
        /// the lift wasn't done that week.
        let best: Double?
    }

    enum Verdict: Equatable {
        /// Not enough weeks with the lift in them to say anything.
        case tooEarly
        /// The metric rose over the window at the average dose.
        case progressing(delta: Double, sets: Double)
        /// Flat for `weeks`, and the dose is under the band: volume is a lever.
        case stalledLow(weeks: Int, sets: Double)
        /// Flat for `weeks` at a dose inside the band.
        case stalledMid(weeks: Int, sets: Double)
        /// Flat for `weeks` at a dose above the band: volume isn't the lever.
        case stalledHigh(weeks: Int, sets: Double)
    }

    let exercise: String
    let muscle: MuscleGroup
    let metric: Analytics.Metric
    let weeks: [Week]
    let verdict: Verdict

    /// The band a programme usually aims for, in hard sets a week.
    static let band = 10.0...20.0

    /// Build for a lift over the last `weeks` weeks. Nil when the lift's muscle
    /// isn't mapped, or the lift never appears in the window.
    static func make(for exercise: String, in sessions: [Session], map: MuscleMap,
                     weeks count: Int = 8, endingOn today: Date = Date(),
                     calendar: Calendar = .current) -> DoseResponse? {
        guard let muscle = map.groups(for: exercise)?.first else { return nil }
        let metric = Analytics.availableMetrics(exercise, in: sessions).first ?? .topSet
        let grid = Analytics.weekGrid(weeks: count, endingOn: today, calendar: calendar, in: sessions)
        let dose = map.weeklySets(weeks: count, endingOn: today, calendar: calendar, in: sessions)
        let series = Analytics.series(exercise, metric: metric, in: sessions)
        let byDay = Dictionary(grouping: series) { Session.dateFormatter.string(from: $0.date) }

        let weeks: [Week] = grid.enumerated().map { i, week in
            let keys = week.days.compactMap { $0?.key }
            let best = keys.flatMap { byDay[$0] ?? [] }.map(\.value).max()
            return Week(start: week.start, sets: dose[i][muscle] ?? 0, best: best)
        }
        guard weeks.contains(where: { $0.best != nil }) else { return nil }
        return DoseResponse(exercise: exercise, muscle: muscle, metric: metric,
                            weeks: weeks, verdict: verdict(for: weeks))
    }

    /// Progressing if the latest week's best beats the best of the earlier
    /// weeks; otherwise flat for as many weeks as it's been since the best was
    /// set. The dose is the average of the last four weeks the lift was done in.
    static func verdict(for weeks: [Week]) -> Verdict {
        let done = weeks.filter { $0.best != nil }
        guard done.count >= 3, let last = done.last, let lastBest = last.best else { return .tooEarly }

        let sets = done.suffix(4).map(\.sets).reduce(0, +) / Double(min(4, done.count))
        let earlier = done.dropLast().compactMap(\.best)
        let previousBest = earlier.max() ?? lastBest
        if lastBest > previousBest {
            return .progressing(delta: lastBest - (earlier.first ?? lastBest), sets: sets)
        }
        // Weeks since the standing best was first hit, counted in weeks the lift was done.
        let bestIndex = done.firstIndex { ($0.best ?? 0) >= previousBest } ?? 0
        let stalled = done.count - 1 - bestIndex
        if sets < band.lowerBound { return .stalledLow(weeks: stalled, sets: sets) }
        if sets > band.upperBound { return .stalledHigh(weeks: stalled, sets: sets) }
        return .stalledMid(weeks: stalled, sets: sets)
    }

    /// The one sentence under the chart.
    var summary: String {
        let name = muscle.rawValue
        func dose(_ s: Double) -> String { String(format: "%.0f %@ sets a week", s, name) }
        switch verdict {
        case .tooEarly:
            return "Too few weeks of \(exercise.replacingOccurrences(of: "-", with: " ")) to read a trend yet."
        case .progressing(let delta, let sets):
            let amount = delta > 0 ? "+\(WorkSet.formatWeight(delta)) \(metric.unit)" : "a new best"
            return "Progressing: \(amount) over the window at \(dose(sets))."
        case .stalledLow(let weeks, let sets):
            return "Flat for \(weeks) \(weeks == 1 ? "week" : "weeks") at \(dose(sets)), under the 10–20 band. Volume is a lever."
        case .stalledMid(let weeks, let sets):
            return "Flat for \(weeks) \(weeks == 1 ? "week" : "weeks") at \(dose(sets)), inside the band. Before adding sets, look at effort, load jumps or a deload."
        case .stalledHigh(let weeks, let sets):
            return "Flat for \(weeks) \(weeks == 1 ? "week" : "weeks") at \(dose(sets)), above the band. Volume isn't the lever; recover, then push effort."
        }
    }
}
