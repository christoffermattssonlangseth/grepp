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
/// day reading as zero triceps work. A lift can be *for* more than one
/// muscle: an overhead press is a full set for the front and the side delts
/// both, since the side head works as hard as the front in it. Isolation
/// lifts count once, for one muscle.
///
/// The built-in table covers the exercise library and the usual aliases. A
/// lift it doesn't know is *unmapped* and counted nowhere — shown as such
/// rather than guessed — until it's assigned in Settings.
struct MuscleMap: Equatable, RawRepresentable {
    typealias Credits = [MuscleGroup: Double]

    /// What a lift is for, and what it also trains: each muscle with the
    /// share of a set it gets. The table uses 1 and ½; a lifter can set any
    /// share from Settings — a quarter for a muscle that only helps, three
    /// quarters for one that nearly limits the lift.
    struct Share: Equatable {
        struct Part: Equatable {
            var group: MuscleGroup
            var weight: Double
        }
        /// In the order they're shown; the first is what the lift is for.
        var parts: [Part]

        /// The muscle a lift's own progress is read against: the heaviest
        /// share, the first of them on a tie.
        var primary: MuscleGroup? {
            guard let top = parts.map(\.weight).max() else { return nil }
            return parts.first { $0.weight == top }?.group
        }

        /// The muscles in order — the lifter's list form.
        var ordered: [MuscleGroup] { parts.map(\.group) }

        func weight(of group: MuscleGroup) -> Double {
            parts.first { $0.group == group }?.weight ?? 0
        }

        /// One muscle it's for, the rest half.
        static func lift(_ full: MuscleGroup, half: MuscleGroup...) -> Share {
            Share(full: [full], half: half)
        }

        static func lift(full: [MuscleGroup], half: [MuscleGroup]) -> Share {
            Share(full: full, half: half)
        }

        /// A lifter's ordered list: the first is what it's for, the rest half.
        init(_ groups: [MuscleGroup]) {
            self.init(full: Array(groups.prefix(1)), half: Array(groups.dropFirst()))
        }

        init(full: [MuscleGroup], half: [MuscleGroup]) {
            self.init(parts: full.map { Part(group: $0, weight: 1) } + half.map { Part(group: $0, weight: 0.5) })
        }

        /// Any weights: biggest share first, body order on a tie, zeros dropped.
        init(weights: Credits) {
            let parts = MuscleGroup.ordered.compactMap { g in
                weights[g].flatMap { $0 > 0 ? Part(group: g, weight: $0) : nil }
            }
            // A stable sort: equal shares keep body order.
            self.init(parts: parts.enumerated().sorted {
                $0.element.weight > $1.element.weight
                    || ($0.element.weight == $1.element.weight && $0.offset < $1.offset)
            }.map(\.element))
        }

        init(parts: [Part]) {
            // One entry per muscle: the first mention wins.
            var seen = Set<MuscleGroup>()
            self.parts = parts.filter { seen.insert($0.group).inserted && $0.weight > 0 }
        }

        var credits: Credits {
            Dictionary(parts.map { ($0.group, $0.weight) }, uniquingKeysWith: { a, _ in a })
        }

        var isEmpty: Bool { parts.isEmpty }

        /// A weight as stored: "1", "0.5", "0.25".
        static func format(_ weight: Double) -> String {
            weight == weight.rounded() ? String(Int(weight)) : String(format: "%g", weight)
        }

        /// A weight as shown: "1", "½", "¼", "¾", else the number.
        static func label(_ weight: Double) -> String {
            switch weight {
            case 0.25: return "¼"
            case 0.5: return "½"
            case 0.75: return "¾"
            default: return format(weight)
            }
        }

        /// "chest 1 · triceps ½ · front delts ½"
        var summary: String {
            parts.map { "\($0.group.rawValue) \(Share.label($0.weight))" }.joined(separator: " · ")
        }
    }

    /// The lifter's own assignments.
    var overrides: [String: Share]

    init(overrides: [String: Share] = [:]) { self.overrides = overrides }

    // MARK: - persistence
    //
    // "seal-row=back:1+biceps:0.5;sled-push=quads:1+core:0.25". A muscle with
    // no share written — how earlier versions stored it — is a full set for
    // the first and half for the rest.

    init?(rawValue: String) {
        var overrides: [String: Share] = [:]
        for entry in rawValue.split(separator: ";") {
            let kv = entry.split(separator: "=")
            guard kv.count == 2 else { continue }
            var parts: [Share.Part] = []
            for (i, item) in kv[1].split(separator: "+").enumerated() {
                let gw = item.split(separator: ":", maxSplits: 1)
                guard let group = MuscleGroup(rawValue: String(gw[0])) else { continue }
                let weight = gw.count == 2 ? Double(gw[1]) ?? 0 : (i == 0 ? 1 : 0.5)
                parts.append(Share.Part(group: group, weight: weight))
            }
            let share = Share(parts: parts)
            guard !share.isEmpty else { continue }
            overrides[MuscleMap.key(String(kv[0]))] = share
        }
        self.overrides = overrides
    }

    var rawValue: String {
        overrides.keys.sorted().map { key in
            let parts = (overrides[key]?.parts ?? []).map { "\($0.group.rawValue):\(Share.format($0.weight))" }
            return "\(key)=\(parts.joined(separator: "+"))"
        }
        .joined(separator: ";")
    }

    // MARK: - lookup

    /// The credits for an exercise; nil when it's unmapped.
    func credits(for exercise: String) -> Credits? { share(for: exercise)?.credits }

    /// What the lifter has said, or what the table says — for showing in Settings.
    func share(for exercise: String) -> Share? {
        let key = MuscleMap.key(exercise)
        // An override on the table's name covers the spellings that point to it.
        return overrides[key]
            ?? MuscleMap.aliases[key].flatMap { overrides[$0] }
            ?? MuscleMap.builtInShare(for: exercise)
    }

    /// The table's answer alone, aliases resolved — what "reset" goes back to.
    static func builtInShare(for exercise: String) -> Share? {
        let key = MuscleMap.key(exercise)
        return builtIn[key] ?? aliases[key].flatMap { builtIn[$0] }
    }

    func isOverridden(_ exercise: String) -> Bool { overrides[MuscleMap.key(exercise)] != nil }

    /// Assign, or clear with an empty list. The first group is the lift's own;
    /// the rest count half.
    mutating func set(_ groups: [MuscleGroup], for exercise: String) {
        set(groups.isEmpty ? nil : Share(groups), for: exercise)
    }

    /// Assign any shares, or clear with nil or an empty share. Setting exactly
    /// what the table says is a clear too: no point remembering the default.
    mutating func set(_ share: Share?, for exercise: String) {
        let key = MuscleMap.key(exercise)
        guard !key.isEmpty else { return }
        if let share, !share.isEmpty, share != MuscleMap.builtInShare(for: exercise) {
            overrides[key] = share
        } else {
            overrides.removeValue(forKey: key)
        }
    }

    /// Every lift the table knows, by its canonical name, in alphabetical order.
    static var tableExercises: [String] { builtIn.keys.sorted() }

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

    /// What each lift is for, and what it also trains.
    static let builtIn: [String: Share] = [
        // Legs
        "squat": .lift(.quads, half: .glutes),
        "front-squat": .lift(.quads, half: .glutes),
        "hack-squat": .lift(.quads, half: .glutes),
        "leg-press": .lift(.quads, half: .glutes),
        "lunge": .lift(.quads, half: .glutes),
        "bulgarian-split-squat": .lift(.quads, half: .glutes),
        "leg-extension": .lift(.quads),
        "romanian-deadlift": .lift(.hamstrings, half: .glutes),
        "stiff-leg-deadlift": .lift(.hamstrings, half: .glutes),
        "good-morning": .lift(.hamstrings, half: .back),
        "leg-curl": .lift(.hamstrings),
        "deadlift": .lift(.hamstrings, half: .glutes, .back),
        "sumo-deadlift": .lift(.glutes, half: .hamstrings, .quads),
        "trap-bar-deadlift": .lift(.quads, half: .glutes, .back),
        "hip-thrust": .lift(.glutes, half: .hamstrings),
        "glute-bridge": .lift(.glutes, half: .hamstrings),
        "calf-raise": .lift(.calves),
        // Push
        "bench-press": .lift(.chest, half: .triceps, .frontDelts),
        "incline-bench-press": .lift(.chest, half: .frontDelts, .triceps),
        "dumbbell-bench-press": .lift(.chest, half: .triceps, .frontDelts),
        "close-grip-bench-press": .lift(.triceps, half: .chest),
        "push-ups": .lift(.chest, half: .triceps),
        "dips": .lift(.chest, half: .triceps),
        "chest-fly": .lift(.chest),
        "over-head-press": .lift(full: [.frontDelts, .sideDelts], half: [.triceps]),
        "push-press": .lift(full: [.frontDelts, .sideDelts], half: [.triceps]),
        "dumbbell-shoulder-press": .lift(full: [.frontDelts, .sideDelts], half: [.triceps]),
        "lateral-raise": .lift(.sideDelts),
        "front-raise": .lift(.frontDelts),
        "tricep-pushdown": .lift(.triceps),
        "skull-crusher": .lift(.triceps),
        "overhead-tricep-extension": .lift(.triceps),
        // Pull
        "barbell-row": .lift(.back, half: .biceps, .rearDelts),
        "pendlay-row": .lift(.back, half: .biceps, .rearDelts),
        "seal-row": .lift(.back, half: .biceps, .rearDelts),
        "dumbbell-row": .lift(.back, half: .biceps, .rearDelts),
        "cable-row": .lift(.back, half: .biceps, .rearDelts),
        "chest-supported-row": .lift(.back, half: .biceps, .rearDelts),
        "upright-row": .lift(.sideDelts, half: .back),
        "pull-ups": .lift(.back, half: .biceps),
        "chin-ups": .lift(.back, half: .biceps),
        "lat-pulldown": .lift(.back, half: .biceps),
        "face-pull": .lift(.rearDelts, half: .back),
        "rear-delt-fly": .lift(.rearDelts),
        "shrug": .lift(.back),
        "dumbbell-curl": .lift(.biceps),
        "barbell-curl": .lift(.biceps),
        "hammer-curl": .lift(.biceps),
        "preacher-curl": .lift(.biceps),
        // Core
        "plank": .lift(.core),
        "hanging-leg-raise": .lift(.core),
        "ab-wheel": .lift(.core),
        "crunch": .lift(.core),
        "cable-crunch": .lift(.core),
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
