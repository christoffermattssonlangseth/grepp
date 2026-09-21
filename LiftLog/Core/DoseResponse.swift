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
        /// Sets of this lift itself that week — the direct lever.
        let liftSets: Int
        /// Days the lift was done that week — the exposures.
        let liftSessions: Int
        /// Weekly sets for the lift's main muscle, every lift that trains it,
        /// credits included — what the 10–20 band is about.
        let sets: Double
        /// The week's best for the lift's own metric (top set, reps…); nil when
        /// the lift wasn't done that week.
        let best: Double?
    }

    enum Verdict: Equatable {
        /// Not enough weeks with the lift in them to say anything.
        case tooEarly
        /// The metric rose over the window at the average dose.
        case progressing(delta: Double, liftSets: Double, sets: Double)
        /// Flat for `weeks`, and the muscle's dose is under the band: volume is a lever.
        case stalledLow(weeks: Int, liftSets: Double, sets: Double)
        /// Flat for `weeks` at a dose inside the band.
        case stalledMid(weeks: Int, liftSets: Double, sets: Double)
        /// Flat for `weeks` at a dose above the band: volume isn't the lever.
        case stalledHigh(weeks: Int, liftSets: Double, sets: Double)
    }

    /// The verdict as a colour would carry it: three states, not five.
    enum State: Equatable {
        case progressing, stalled, tooEarly
    }

    let exercise: String
    let muscle: MuscleGroup
    let metric: Analytics.Metric
    let weeks: [Week]
    let verdict: Verdict

    var state: State {
        switch verdict {
        case .tooEarly: return .tooEarly
        case .progressing: return .progressing
        case .stalledLow, .stalledMid, .stalledHigh: return .stalled
        }
    }

    /// The verdict as a session: the last session with the one change the
    /// verdict asks for, ready for the Log tab. Nil when there is nothing to
    /// change — progressing, or too early to say.
    struct NextStep: Equatable {
        let label: String
        let entry: ExerciseEntry
    }

    func nextStep(in sessions: [Session]) -> NextStep? {
        guard let last = Programme.lastDone(exercise, in: sessions)?.entry, !last.sets.isEmpty else { return nil }
        let sets = last.sets.map { WorkSet(weight: $0.weight, added: $0.added, reps: $0.reps) }
        switch verdict {
        case .tooEarly, .progressing:
            return nil
        case .stalledLow:
            // Under the band: one more set, a copy of the last one.
            return NextStep(label: "one more set",
                            entry: ExerciseEntry(name: last.name, sets: sets + [sets[sets.count - 1]]))
        case .stalledMid:
            // Inside it: the same loads, one more rep on the set that counts.
            var next = sets
            if let top = ReversePyramid.topSet(of: last), let i = sets.firstIndex(of: top) {
                next[i] = WorkSet(weight: top.weight, added: top.added, reps: top.reps + 1)
            }
            return NextStep(label: "one more rep on the top set", entry: ExerciseEntry(name: last.name, sets: next))
        case .stalledHigh:
            // Above it: a lighter session, a tenth off every set, to recover.
            let lighter = sets.map { set -> WorkSet in
                if let w = set.weight { return WorkSet(weight: (w * 0.9 / 2.5).rounded() * 2.5, added: nil, reps: set.reps) }
                if let a = set.added { let less = a - 2.5; return WorkSet(weight: nil, added: less > 0 ? less : nil, reps: set.reps) }
                return WorkSet(weight: nil, added: nil, reps: max(1, set.reps - 2))
            }
            return NextStep(label: "a lighter session, a tenth off", entry: ExerciseEntry(name: last.name, sets: lighter))
        }
    }

    /// The verdict in a few characters, for a row in a list: what it moved
    /// by, or how long it has stood.
    var short: String {
        switch verdict {
        case .tooEarly: return "too early"
        case .progressing(let delta, _, _): return "+\(WorkSet.formatWeight(delta)) \(metric.unit)"
        case .stalledLow(let weeks, _, _), .stalledMid(let weeks, _, _), .stalledHigh(let weeks, _, _):
            return "flat \(weeks) \(weeks == 1 ? "week" : "weeks")"
        }
    }

    /// Every lift in the log read at once, for a list that colours each one.
    /// Lifts whose muscle isn't mapped, or that haven't been done in the
    /// window, are left out: nothing to say is not a state.
    static func all(for exercises: [String], in sessions: [Session], map: MuscleMap,
                    endingOn today: Date = Date(), calendar: Calendar = .current) -> [String: DoseResponse] {
        var out: [String: DoseResponse] = [:]
        for exercise in exercises {
            if let dose = make(for: exercise, in: sessions, map: map, endingOn: today, calendar: calendar) {
                out[exercise] = dose
            }
        }
        return out
    }

    /// The band a programme usually aims for, in hard sets a week. One
    /// number for the bars, the verdict and the coach's rule alike.
    static let band = 10.0...20.0

    /// Build for a lift over the last `weeks` weeks. Nil when the lift's muscle
    /// isn't mapped, or the lift never appears in the window.
    static func make(for exercise: String, in sessions: [Session], map: MuscleMap,
                     weeks count: Int = 8, endingOn today: Date = Date(),
                     calendar: Calendar = .current) -> DoseResponse? {
        guard let muscle = map.share(for: exercise)?.primary else { return nil }
        let metric = Analytics.availableMetrics(exercise, in: sessions).first ?? .topSet
        let grid = Analytics.weekGrid(weeks: count, endingOn: today, calendar: calendar, in: sessions)
        let dose = map.weeklySets(weeks: count, endingOn: today, calendar: calendar, in: sessions)
        let series = Analytics.series(exercise, metric: metric, in: sessions, through: today)
        let byDay = Dictionary(grouping: series) { Session.dateFormatter.string(from: $0.date) }

        let sessionsByDay = Dictionary(grouping: sessions, by: \.dateString)
        // Plain loops, in steps: one chained expression here sent the type
        // checker off for a walk it didn't come back from.
        var weeks: [Week] = []
        for (i, week) in grid.enumerated() {
            let keys: [String] = week.days.compactMap { $0?.key }
            var bests: [Double] = []
            var own = 0
            var days = 0
            for key in keys {
                for point in byDay[key] ?? [] { bests.append(point.value) }
                var doneToday = false
                for session in sessionsByDay[key] ?? [] {
                    for entry in Analytics.entries(exercise, in: session) {
                        own += entry.sets.count
                        doneToday = true
                    }
                }
                if doneToday { days += 1 }
            }
            let muscleSets: Double = dose[i][muscle] ?? 0
            weeks.append(Week(start: week.start, liftSets: own, liftSessions: days, sets: muscleSets, best: bests.max()))
        }
        guard weeks.contains(where: { $0.best != nil }) else { return nil }
        return DoseResponse(exercise: exercise, muscle: muscle, metric: metric,
                            weeks: weeks, verdict: verdict(for: weeks))
    }

    /// Progressing if the best of the last two weeks the lift was done beats
    /// everything before them — one bad session after a record is not a
    /// stall. Otherwise flat for as many calendar weeks as it's been since
    /// the standing best was first hit, counted to the last week the lift
    /// was done. The dose is the average of the last four completed weeks it
    /// was done in; the week in progress is left out of it.
    static func verdict(for weeks: [Week]) -> Verdict {
        let done = weeks.filter { $0.best != nil }
        guard done.count >= 3 else { return .tooEarly }

        // The last week of the grid is the one in progress: a Monday's two sets
        // are not a week's dose. It counts for the result, not for the dose.
        let completed = done.filter { $0.start != weeks.last?.start }
        let recent = Array((completed.isEmpty ? done : completed).suffix(4))
        var setSum = 0.0
        var ownSum = 0
        for week in recent {
            setSum += week.sets
            ownSum += week.liftSets
        }
        let sets = setSum / Double(recent.count)
        let own = Double(ownSum) / Double(recent.count)

        let latest = done.suffix(2).compactMap(\.best).max() ?? 0
        let earlier = done.dropLast(2).compactMap(\.best)
        if let previousBest = earlier.max(), latest > previousBest {
            return .progressing(delta: latest - (earlier.first ?? latest), liftSets: own, sets: sets)
        }
        // Calendar weeks from the week the standing best was first hit to the
        // last week the lift was done — a lift done every third week that
        // hasn't moved in three sessions has been flat for six weeks, not two.
        let standing = done.compactMap(\.best).max() ?? 0
        let bestIndex = weeks.firstIndex { ($0.best ?? -.infinity) >= standing } ?? 0
        let lastDone = weeks.lastIndex { $0.best != nil } ?? bestIndex
        let stalled = max(0, lastDone - bestIndex)
        if sets < band.lowerBound { return .stalledLow(weeks: stalled, liftSets: own, sets: sets) }
        if sets > band.upperBound { return .stalledHigh(weeks: stalled, liftSets: own, sets: sets) }
        return .stalledMid(weeks: stalled, liftSets: own, sets: sets)
    }

    /// Days the lift was done a week, averaged over the weeks it was done in.
    var sessionsPerWeek: Double {
        let done = weeks.filter { $0.best != nil }
        guard !done.isEmpty else { return 0 }
        return Double(done.map(\.liftSessions).reduce(0, +)) / Double(done.count)
    }

    /// The one sentence under the chart. Leads with the lift's own sets, the
    /// direct lever; the muscle's total in brackets is what the band judges.
    var summary: String {
        let lift = exercise.replacingOccurrences(of: "-", with: " ")
        func dose(_ own: Double, _ all: Double) -> String {
            let ownText = String(format: "%.0f", own)
            let allText = String(format: "%.0f", all)
            return "\(ownText) \(lift) sets a week (\(allText) for \(muscle.rawValue) in all)"
        }
        func flat(_ weeks: Int) -> String { "Flat for \(weeks) \(weeks == 1 ? "week" : "weeks")" }
        let band = "\(Int(DoseResponse.band.lowerBound))–\(Int(DoseResponse.band.upperBound))"
        let verdictText: String
        switch verdict {
        case .tooEarly:
            return "Too few weeks of \(lift) to read a trend yet."
        case .progressing(let delta, let own, let all):
            verdictText = "Progressing: +\(WorkSet.formatWeight(delta)) \(metric.unit) over the window at \(dose(own, all))."
        case .stalledLow(let weeks, let own, let all):
            verdictText = "\(flat(weeks)) at \(dose(own, all)), under the \(band) band. Volume is a lever: another \(lift) set, or a second day."
        case .stalledMid(let weeks, let own, let all):
            verdictText = "\(flat(weeks)) at \(dose(own, all)), inside the band. Before adding sets, look at effort, load jumps or a deload."
        case .stalledHigh(let weeks, let own, let all):
            verdictText = "\(flat(weeks)) at \(dose(own, all)), above the band. Volume isn't the lever; recover, then push effort."
        }
        return verdictText + " " + frequencyText
    }

    /// "Done twice a week." — an observation, not a target.
    var frequencyText: String {
        let f = sessionsPerWeek
        let times: String
        if f == 1 { times = "once" }
        else if f == 2 { times = "twice" }
        else if f == f.rounded() { times = "\(Int(f)) times" }
        else { times = String(format: "%.1f times", f) }
        return "Done \(times) a week."
    }

    /// The card, as a question for the coach: the verdict and the eight
    /// weeks behind it, so the answer is about this stall and not a re-read.
    func coachQuestion(today: Date = Date(), calendar: Calendar = .current) -> String {
        let lift = exercise.replacingOccurrences(of: "-", with: " ")
        let rows = weeks.map { week -> String in
            let start = Session.dateFormatter.string(from: week.start)
            let best = week.best.map { "best \(WorkSet.formatWeight($0)) \(metric.unit)" } ?? "not done"
            let all = week.sets == week.sets.rounded() ? String(Int(week.sets)) : String(format: "%.1f", week.sets)
            return "- week of \(start): \(week.liftSets) \(lift) sets over \(week.liftSessions) \(week.liftSessions == 1 ? "day" : "days"), \(all) \(muscle.rawValue) sets in all, \(best)"
        }
        return """
        Trends reads my \(lift) as: \(summary)

        The last \(weeks.count) weeks, \(metric.rawValue.lowercased()) per week:
        \(rows.joined(separator: "\n"))

        Do you read it the same way, and what's the way out?
        """
    }
}
