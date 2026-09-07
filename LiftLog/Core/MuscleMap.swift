import Foundation

/// The body parts a set can be counted toward. At the level a programme is
/// written — not "legs", but the muscles a weekly set target is set for.
enum MuscleGroup: String, CaseIterable, Codable, Identifiable {
    case quads, hamstrings, glutes, calves
    case chest, triceps
    // Delts split three ways: a bench day's front-delt work must not read as
    // side-delt volume, which is the one that's usually short.
    case frontDelts = "front delts", sideDelts = "side delts", rearDelts = "rear delts"
    case back, biceps
    case core
    var id: String { rawValue }

    /// Display order: lower body, push, pull, trunk.
    static let ordered: [MuscleGroup] = allCases
}

/// Which muscles an exercise's sets count toward, and how much.
///
/// A set of a compound lift counts fully for the muscle it's a lift *for* and
/// half for each muscle that also does real work in it — bench is a chest
/// set, half a triceps set and half a front-delt set; squat a quad set and
/// half a glute set; a row a back set, half biceps, half rear delts. That's
/// the convention weekly set counts are usually kept in, and it stops a bench
/// day reading as zero triceps work. Isolation lifts count once, for one muscle.
///
/// The built-in table covers the exercise library and the usual aliases. A
/// lift it doesn't know is *unmapped* and counted nowhere — shown as such
/// rather than guessed — until it's assigned in Settings.
struct MuscleMap: Equatable, RawRepresentable {
    typealias Credits = [MuscleGroup: Double]

    /// The lifter's own assignments: primary first, then the halves.
    var overrides: [String: [MuscleGroup]]

    init(overrides: [String: [MuscleGroup]] = [:]) { self.overrides = overrides }

    // MARK: - persistence ("seal-row=back+biceps;sled-push=quads")

    init?(rawValue: String) {
        var overrides: [String: [MuscleGroup]] = [:]
        for entry in rawValue.split(separator: ";") {
            let kv = entry.split(separator: "=")
            guard kv.count == 2 else { continue }
            let groups = kv[1].split(separator: "+").compactMap { MuscleGroup(rawValue: String($0)) }
            guard !groups.isEmpty else { continue }
            overrides[MuscleMap.key(String(kv[0]))] = groups
        }
        self.overrides = overrides
    }

    var rawValue: String {
        overrides.keys.sorted()
            .map { "\($0)=\((overrides[$0] ?? []).map(\.rawValue).joined(separator: "+"))" }
            .joined(separator: ";")
    }

    // MARK: - lookup

    /// The credits for an exercise; nil when it's unmapped.
    func credits(for exercise: String) -> Credits? {
        let key = MuscleMap.key(exercise)
        if let groups = overrides[key] { return MuscleMap.credits(groups) }
        if let groups = MuscleMap.builtIn[key] { return MuscleMap.credits(groups) }
        if let alias = MuscleMap.aliases[key], let groups = MuscleMap.builtIn[alias] {
            return MuscleMap.credits(groups)
        }
        return nil
    }

    /// What the lifter has said, or what the table says — for showing in Settings.
    func groups(for exercise: String) -> [MuscleGroup]? {
        let key = MuscleMap.key(exercise)
        return overrides[key] ?? MuscleMap.builtIn[key]
            ?? MuscleMap.aliases[key].flatMap { MuscleMap.builtIn[$0] }
    }

    func isOverridden(_ exercise: String) -> Bool { overrides[MuscleMap.key(exercise)] != nil }

    /// Assign, or clear with an empty list. The first group is the lift's own;
    /// the rest count half.
    mutating func set(_ groups: [MuscleGroup], for exercise: String) {
        let key = MuscleMap.key(exercise)
        guard !key.isEmpty else { return }
        if groups.isEmpty { overrides.removeValue(forKey: key) } else { overrides[key] = groups }
    }

    /// Exercises in these sessions that count nowhere yet, most recent first.
    func unmapped(in sessions: [Session]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in sessions.sorted(by: { $0.date > $1.date }) {
            for ex in session.exercises {
                let key = MuscleMap.key(ex.name)
                guard !seen.contains(key), credits(for: ex.name) == nil else { continue }
                seen.insert(key)
                result.append(ex.name)
            }
        }
        return result
    }

    // MARK: - counting

    /// Sets per muscle for one exercise: every logged set is a working set.
    func sets(for exercise: ExerciseEntry) -> Credits {
        guard let credits = credits(for: exercise.name) else { return [:] }
        return credits.mapValues { $0 * Double(exercise.sets.count) }
    }

    /// Sets per muscle over any run of sessions — a workout, a week, a block.
    func sets(in sessions: [Session]) -> Credits {
        var total: Credits = [:]
        for session in sessions {
            for exercise in session.exercises {
                for (group, count) in sets(for: exercise) {
                    total[group, default: 0] += count
                }
            }
        }
        return total
    }

    /// Sets per muscle for each of the last `weeks` weeks, Monday-first, oldest
    /// first. Matched on the log's own date key, like the training-days grid.
    func weeklySets(weeks: Int, endingOn today: Date = Date(),
                    calendar: Calendar = .current, in sessions: [Session]) -> [Credits] {
        let grid = Analytics.weekGrid(weeks: weeks, endingOn: today, calendar: calendar, in: sessions)
        let byDay = Dictionary(grouping: sessions, by: \.dateString)
        return grid.map { week in
            let keys = week.days.compactMap { $0?.key }
            return sets(in: keys.flatMap { byDay[$0] ?? [] })
        }
    }

    // MARK: - the table

    static func key(_ exercise: String) -> String {
        exercise.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func credits(_ groups: [MuscleGroup]) -> Credits {
        var credits: Credits = [:]
        for (i, group) in groups.enumerated() where credits[group] == nil {
            credits[group] = i == 0 ? 1 : 0.5
        }
        return credits
    }

    /// Primary first, then what counts half.
    static let builtIn: [String: [MuscleGroup]] = [
        // Legs
        "squat": [.quads, .glutes],
        "front-squat": [.quads, .glutes],
        "hack-squat": [.quads, .glutes],
        "leg-press": [.quads, .glutes],
        "lunge": [.quads, .glutes],
        "bulgarian-split-squat": [.quads, .glutes],
        "leg-extension": [.quads],
        "romanian-deadlift": [.hamstrings, .glutes],
        "stiff-leg-deadlift": [.hamstrings, .glutes],
        "good-morning": [.hamstrings, .back],
        "leg-curl": [.hamstrings],
        "deadlift": [.hamstrings, .glutes, .back],
        "sumo-deadlift": [.glutes, .hamstrings, .quads],
        "trap-bar-deadlift": [.quads, .glutes, .back],
        "hip-thrust": [.glutes, .hamstrings],
        "glute-bridge": [.glutes, .hamstrings],
        "calf-raise": [.calves],
        // Push
        "bench-press": [.chest, .triceps, .frontDelts],
        "incline-bench-press": [.chest, .frontDelts, .triceps],
        "dumbbell-bench-press": [.chest, .triceps, .frontDelts],
        "close-grip-bench-press": [.triceps, .chest],
        "push-ups": [.chest, .triceps],
        "dips": [.chest, .triceps],
        "chest-fly": [.chest],
        "over-head-press": [.frontDelts, .triceps, .sideDelts],
        "push-press": [.frontDelts, .triceps, .sideDelts],
        "dumbbell-shoulder-press": [.frontDelts, .triceps, .sideDelts],
        "lateral-raise": [.sideDelts],
        "front-raise": [.frontDelts],
        "tricep-pushdown": [.triceps],
        "skull-crusher": [.triceps],
        "overhead-tricep-extension": [.triceps],
        // Pull
        "barbell-row": [.back, .biceps, .rearDelts],
        "pendlay-row": [.back, .biceps, .rearDelts],
        "seal-row": [.back, .biceps, .rearDelts],
        "dumbbell-row": [.back, .biceps, .rearDelts],
        "cable-row": [.back, .biceps, .rearDelts],
        "chest-supported-row": [.back, .biceps, .rearDelts],
        "upright-row": [.sideDelts, .back],
        "pull-ups": [.back, .biceps],
        "chin-ups": [.back, .biceps],
        "lat-pulldown": [.back, .biceps],
        "face-pull": [.rearDelts, .back],
        "rear-delt-fly": [.rearDelts],
        "shrug": [.back],
        "dumbbell-curl": [.biceps],
        "barbell-curl": [.biceps],
        "hammer-curl": [.biceps],
        "preacher-curl": [.biceps],
        // Core
        "plank": [.core],
        "hanging-leg-raise": [.core],
        "ab-wheel": [.core],
        "crunch": [.core],
        "cable-crunch": [.core],
    ]

    /// The way people actually write them in a log.
    static let aliases: [String: String] = [
        "bench": "bench-press", "flat-bench": "bench-press", "incline-bench": "incline-bench-press",
        "incline-press": "incline-bench-press", "db-bench": "dumbbell-bench-press",
        "ohp": "over-head-press", "overhead-press": "over-head-press", "press": "over-head-press",
        "military-press": "over-head-press", "shoulder-press": "dumbbell-shoulder-press",
        "rdl": "romanian-deadlift", "sldl": "stiff-leg-deadlift", "dl": "deadlift",
        "back-squat": "squat", "squats": "squat", "hip-thrusts": "hip-thrust",
        "row": "barbell-row", "bent-over-row": "barbell-row", "rows": "barbell-row",
        "db-row": "dumbbell-row", "one-arm-row": "dumbbell-row",
        "pullup": "pull-ups", "pullups": "pull-ups", "pull-up": "pull-ups",
        "chinup": "chin-ups", "chinups": "chin-ups", "chin-up": "chin-ups",
        "pulldown": "lat-pulldown", "lat-pull-down": "lat-pulldown",
        "curl": "dumbbell-curl", "curls": "dumbbell-curl", "bicep-curl": "dumbbell-curl",
        "pushdown": "tricep-pushdown", "triceps-pushdown": "tricep-pushdown",
        "dip": "dips", "pushup": "push-ups", "pushups": "push-ups", "push-up": "push-ups",
        "calf-raises": "calf-raise", "calves": "calf-raise",
        "lunges": "lunge", "split-squat": "bulgarian-split-squat",
        "leg-raise": "hanging-leg-raise", "leg-raises": "hanging-leg-raise",
        "ab-rollout": "ab-wheel", "crunches": "crunch", "shrugs": "shrug",
        "lateral-raises": "lateral-raise", "side-raise": "lateral-raise",
        "face-pulls": "face-pull", "fly": "chest-fly", "flyes": "chest-fly",
    ]
}
