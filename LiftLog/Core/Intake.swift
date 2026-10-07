import Foundation

/// What a new lifter tells the app once, at the start: how long they have
/// trained, what for, how often, where and with what, and what to work
/// around. Asked on native screens so it works with or without a coach key,
/// and written into the brief files the coach already reads — the facts
/// into coaching.md, the goal into goals.md — so nothing is asked twice.
struct Intake: Equatable, Codable {
    enum Experience: String, CaseIterable, Codable {
        case new, some, years
        var label: String {
            switch self {
            case .new: return "New to lifting"
            case .some: return "Some months"
            case .years: return "A year or more"
            }
        }
        var line: String {
            switch self {
            case .new: return "new to lifting"
            case .some: return "some months of lifting"
            case .years: return "a year or more of lifting"
            }
        }
    }

    enum Goal: String, CaseIterable, Codable {
        case strength, muscle, fitness, sport
        var label: String {
            switch self {
            case .strength: return "Get stronger"
            case .muscle: return "Build muscle"
            case .fitness: return "General fitness"
            case .sport: return "For a sport"
            }
        }
    }

    enum Place: String, CaseIterable, Codable {
        case gym, home, bodyweight
        var label: String {
            switch self {
            case .gym: return "A gym"
            case .home: return "A home gym"
            case .bodyweight: return "No equipment"
            }
        }
        var line: String {
            switch self {
            case .gym: return "a commercial gym"
            case .home: return "a home gym"
            case .bodyweight: return "home, bodyweight only"
            }
        }
    }

    enum Equipment: String, CaseIterable, Codable, Hashable {
        case barbell, bench, dumbbells, cables, pullUpBar, machines
        var label: String {
            switch self {
            case .barbell: return "Barbell and rack"
            case .bench: return "Bench"
            case .dumbbells: return "Dumbbells"
            case .cables: return "Cables"
            case .pullUpBar: return "Pull-up bar"
            case .machines: return "Machines"
            }
        }
    }

    var experience: Experience = .new
    var goal: Goal = .strength
    /// Their goal in their own words, optional: "squat my bodyweight".
    var goalWords = ""
    var goalBy: Date?
    var days = 3
    var minutes = 60
    var place: Place = .gym
    var equipment: Set<Equipment> = Set(Equipment.allCases)
    /// Injuries or limits, in their words; optional.
    var limits = ""

    var isNovice: Bool { experience == .new }

    /// What a place usually has, as the checklist's starting point.
    static func defaultEquipment(for place: Place) -> Set<Equipment> {
        switch place {
        case .gym: return Set(Equipment.allCases)
        case .home: return [.barbell, .bench, .dumbbells, .pullUpBar]
        case .bodyweight: return []
        }
    }

    // MARK: - Into the brief files

    static let heading = "## About me"

    /// The block for coaching.md, under its own heading so it can be
    /// replaced when the setup is run again without touching anything else.
    func coachingSection() -> String {
        var lines = [Intake.heading, "",
                     "- Experience: \(experience.line)",
                     "- Goal: \(goal.label.lowercased())" + (goalWords.trimmed.isEmpty ? "" : " — \(goalWords.trimmed)"),
                     "- Trains \(days) \(days == 1 ? "day" : "days") a week, about \(minutes) minutes a session",
                     "- Trains at \(place.line)"]
        let kit = Equipment.allCases.filter(equipment.contains).map { $0.label.lowercased() }
        if place != .bodyweight {
            lines.append("- Equipment: " + (kit.isEmpty ? "none listed" : kit.joined(separator: ", ")))
        }
        if !limits.trimmed.isEmpty { lines.append("- Work around: \(limits.trimmed)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// coaching.md with the setup's section in it: replacing an earlier one
    /// in place, or put first. Everything else in the file is kept as written.
    static func merging(_ section: String, into coaching: String) -> String {
        var lines = coaching.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) {
            var end = start + 1
            while end < lines.count, !lines[end].hasPrefix("#") { end += 1 }
            var replacement = section.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if end < lines.count, replacement.last != "" { replacement.append("") }
            lines.replaceSubrange(start..<end, with: replacement)
            return lines.joined(separator: "\n")
        }
        let rest = coaching.trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? section : section + "\n" + coaching
    }

    /// The goal as a goals.md line, when they gave one in their own words.
    func goalsLine(calendar: Calendar = .current) -> String? {
        let words = goalWords.trimmed
        guard !words.isEmpty else { return nil }
        guard let goalBy else { return "- \(words)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "d MMM yyyy"
        return "- \(words) by \(f.string(from: goalBy))"
    }

    /// goals.md with the goal added, unless the same line is there already.
    static func adding(_ line: String, to goals: String) -> String {
        let current = goals.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty { return "# Goals\n\n\(line)\n" }
        if goals.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == line }) { return goals }
        return current + "\n" + line + "\n"
    }

    // MARK: - Handing over

    /// What the coach is asked once the setup is done.
    var coachQuestion: String {
        if isNovice {
            return "I've just set up the app and I'm new to lifting. Write me a first programme from my setup in your brief — my days, equipment and goal — and ask only what you still need."
        }
        return "I've just set up the app. Help me bring my last few weeks of training into the log."
    }

    // MARK: - A first programme without a coach

    /// Two full-body days to alternate, fitted to what they have: a barbell,
    /// dumbbells, or nothing. Every session, a lift whose sets all hit the
    /// top of the range goes up next time. Written in the file's own shape,
    /// so Load this day and the editor read it like any other.
    func starter() -> String {
        let pull: String
        if equipment.contains(.pullUpBar) {
            pull = "- chin-ups 3xAMRAP — add a rep when you can; add load once all sets reach 10"
        } else if equipment.contains(.cables) || equipment.contains(.machines) {
            pull = "- lat-pulldown 3x8-10 — add 2.5 kg once all sets hit 10"
        } else {
            pull = "- dumbbell-row 3x8-10 — add 2 kg once all sets hit 10"
        }
        let a: [String], b: [String]
        if equipment.contains(.barbell) {
            let press = equipment.contains(.bench) ? "- bench-press 3x5 — add 2.5 kg when all sets hit 5"
                                                   : "- push-ups 3xAMRAP — add a rep a set when you can"
            a = ["- squat 3x5 — add 5 kg when all sets hit 5", press,
                 "- barbell-row 3x8 — add 2.5 kg when all sets hit 8"]
            b = ["- squat 3x5 — add 5 kg when all sets hit 5",
                 "- over-head-press 3x5 — add 2.5 kg when all sets hit 5",
                 "- deadlift 1x5 — add 5 kg when the set hits 5", pull]
        } else if equipment.contains(.dumbbells) {
            let press = equipment.contains(.bench) ? "- dumbbell-bench-press 3x8-10 — add 2 kg once all sets hit 10"
                                                   : "- push-ups 3xAMRAP — add a rep a set when you can"
            a = ["- bulgarian-split-squat 3x8-10 — add 2 kg once all sets hit 10", press,
                 "- dumbbell-row 3x8-10 — add 2 kg once all sets hit 10"]
            b = ["- romanian-deadlift 3x8-10 — add 2 kg once all sets hit 10",
                 "- dumbbell-shoulder-press 3x8-10 — add 2 kg once all sets hit 10", pull]
        } else {
            a = ["- bulgarian-split-squat 3x10-15 — slower, then more reps",
                 "- push-ups 3xAMRAP — add a rep a set when you can",
                 equipment.contains(.pullUpBar) ? pull : "- glute-bridge 3x12-15 — pause at the top"]
            b = ["- lunge 3x10-15 — longer steps as it gets easy",
                 "- dips 3xAMRAP — from a chair or bench; add a rep when you can",
                 "- plank 3x30-60 — seconds, not reps"]
        }
        let often = days >= 3 ? "Three days a week" : "\(days) \(days == 1 ? "day" : "days") a week"
        return """
        # Beginner, full body

        \(often), alternating the two days: A, B, A, then B, A, B. Start light enough that every rep is clean, and leave a rep or two in the tank. Each line says when it goes up: when every set reaches the reps, add the weight next time. When a lift misses twice in a row, take a tenth off and build back. Load this day on the Programme screen puts the next day in the Log tab.

        ## Day A
        \(a.joined(separator: "\n"))

        ## Day B
        \(b.joined(separator: "\n"))

        """
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
