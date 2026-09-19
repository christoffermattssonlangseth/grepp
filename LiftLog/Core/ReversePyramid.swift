import Foundation

/// Reverse pyramid training: the heaviest set first, while fresh, then each
/// set after it about a tenth lighter for a couple more reps. The top set
/// is the one that counts — when it reaches the top of its rep range the
/// load goes up next time; otherwise the same load again, aiming for one
/// more rep. Loads are arithmetic on the last session, so the app does
/// them itself: no coach, no cost, the same answer every time.
enum ReversePyramid {
    /// How much lighter each set after the top set is.
    static let drop = 0.10
    /// How many more reps each set after the top set aims for.
    static let repStep = 2

    /// The step up when the top set hits its range: bigger on the lifts that
    /// carry the most, the usual 2.5 elsewhere and on anything hung on a belt.
    static func increment(for name: String) -> Double {
        let key = MuscleMap.canonical(name)
        return key.contains("squat") || key.contains("deadlift") ? 5 : 2.5
    }

    /// Today's sets for a lift from its last session: nil with no history to
    /// count from — a first session is the lifter's call, not a formula's.
    static func plan(_ name: String, sets count: Int, reps: ClosedRange<Int>, last: ExerciseEntry?,
                     bar: Double = 20, inventory: PlateInventory = .standard) -> [WorkSet]? {
        guard let last, count > 0, let top = topSet(of: last) else { return nil }
        let hit = top.reps >= reps.upperBound
        // Hit the range: up a step and back to its bottom. Short of it: the same
        // load, one more rep than last time, never past the top of the range.
        let topReps = hit ? reps.lowerBound : min(reps.upperBound, max(reps.lowerBound, top.reps + 1))
        let step = increment(for: name)

        if let weight = top.weight {
            let topWeight = hit ? weight + step : weight
            return (0..<count).map { i in
                let reps = topReps + repStep * i
                guard i > 0 else { return WorkSet(weight: topWeight, added: nil, reps: reps) }
                // To the nearest pair of small plates, then to what the rack can
                // actually make, at or just under that. Under the bar, the number
                // stands as it is: the bar is a loading fact, not a floor — a
                // back-off is never heavier than the top set.
                let raw = (topWeight * pow(1 - drop, Double(i)) / 2.5).rounded() * 2.5
                let loadable = raw < bar ? raw : (PlateMath.load(raw, bar: bar, inventory: inventory)?.total ?? raw)
                return WorkSet(weight: min(topWeight, loadable), added: nil, reps: reps)
            }
        }

        // A bodyweight lift: the load is what's hung on, and a tenth of a
        // body is unknowable, so each set after the top drops one step of it.
        let added = top.added ?? 0
        let topAdded = hit ? added + step : added
        return (0..<count).map { i in
            let extra = max(0, topAdded - step * Double(i))
            return WorkSet(weight: nil, added: extra > 0 ? extra : nil, reps: topReps + repStep * i)
        }
    }

    /// The set that counts: the heaviest, and at equal load the one with most reps.
    static func topSet(of entry: ExerciseEntry) -> WorkSet? {
        entry.sets.max { a, b in
            let la = Analytics.load(of: a), lb = Analytics.load(of: b)
            return la != lb ? la < lb : a.reps < b.reps
        }
    }

    /// A programme day as today's session: reverse pyramid lifts computed
    /// from their last session, any other lift as its last session was, and
    /// the names of lifts with no history to start from.
    static func plan(day: Programme.Day, in sessions: [Session],
                     bar: (String) -> Double, inventory: PlateInventory) -> (entries: [ExerciseEntry], missing: [String]) {
        var entries: [ExerciseEntry] = []
        var missing: [String] = []
        for exercise in day.exercises {
            let last = Programme.lastDone(exercise.name, in: sessions)?.entry
            // Under the log's own spelling, so the history stays one line of
            // lifts rather than splitting into the programme's name and the log's.
            let name = last?.name ?? exercise.name
            if exercise.rpt, let scheme = exercise.setsAndReps,
               let sets = plan(exercise.name, sets: scheme.sets, reps: scheme.reps, last: last,
                               bar: bar(exercise.name), inventory: inventory) {
                entries.append(ExerciseEntry(name: name, sets: sets))
            } else if let last, !last.sets.isEmpty {
                entries.append(ExerciseEntry(name: name, sets: last.sets.map { WorkSet(weight: $0.weight, added: $0.added, reps: $0.reps) }))
            } else {
                missing.append(exercise.name)
            }
        }
        return (entries, missing)
    }

    /// A three-day starter in the file's own shape, written for the app: one
    /// heavy compound first each day, a couple of lifts after it.
    static let starter = """
    # Reverse pyramid, 3 days

    Three days a week. The heaviest set comes first, while you're fresh; each set after it is about a tenth lighter for two more reps. The top set is the one that counts: when it reaches the top of its range, the load goes up next time — 5 kg on squat and deadlift, 2.5 kg elsewhere. Short of the range, same load, one more rep. Rest three to five minutes before the heavy sets. Lines marked rpt are worked out by the app from your last session; Load this day on the Programme screen puts the whole day in the Log tab.

    ## Day A — Pull
    - deadlift rpt 2x4-6 — top set, then one at −10%
    - chin-ups rpt 3x5-7 — add load when the top set hits 7
    - barbell-row 3x8-10 — add 2.5 kg once 3x10

    ## Day B — Push
    - bench-press rpt 3x6-8
    - over-head-press rpt 3x6-8
    - tricep-pushdown 2x10-12 — add 2.5 kg once 2x12

    ## Day C — Legs
    - squat rpt 3x6-8
    - romanian-deadlift 2x8-10 — add 2.5 kg once 2x10
    - calf-raise 3x10-12
    """
}
