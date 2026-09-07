import Foundation

/// A programme as `program.md` holds it: days under `##` headings, one lift
/// per bullet with its set scheme. Written by the coach, saved by the lifter,
/// edited by hand like the other brief files.
///
///     ## Day A — Lower
///     - squat 3x5 — add 2.5 kg when all sets hit
///     - romanian-deadlift 3x8–10
///
/// Loads are deliberately not in the file: the coach picks them from the log
/// each time a day is asked for, which is the whole point of having a coach.
struct Programme: Equatable {
    struct Exercise: Equatable, Identifiable {
        var id: String { "\(name) \(scheme)" }
        let name: String
        /// "3x5", "3x8–10", "3xAMRAP" — as written, not parsed further.
        let scheme: String
        /// Whatever followed " — " on the line: the progression rule, a cue.
        let note: String
    }

    struct Day: Equatable, Identifiable {
        var id: String { title }
        let title: String
        let exercises: [Exercise]
    }

    let title: String
    let days: [Day]

    var isEmpty: Bool { days.isEmpty }

    /// Every bullet under a `##` heading that starts with a lift name. Prose
    /// between days is skipped; a `#` title becomes the programme's name.
    static func parse(_ markdown: String) -> Programme {
        var title = ""
        var days: [Day] = []
        var current: (title: String, exercises: [Exercise])?

        func closeDay() {
            if let current, !current.exercises.isEmpty {
                days.append(Day(title: current.title, exercises: current.exercises))
            }
            current = nil
        }

        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                closeDay()
                current = (String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
            } else if line.hasPrefix("# ") {
                if title.isEmpty { title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            } else if line.hasPrefix("- ") || line.hasPrefix("* "), current != nil {
                if let exercise = parseExercise(String(line.dropFirst(2))) {
                    current?.exercises.append(exercise)
                }
            }
        }
        closeDay()
        return Programme(title: title, days: days)
    }

    // MARK: - Against the log

    /// Which day comes next: the one after the day most recently done, judged
    /// by which day's lifts a session covered best. The first day when nothing
    /// in the log matches any day, or when the programme has one day.
    func dueDayIndex(in sessions: [Session]) -> Int {
        guard days.count > 1 else { return 0 }
        for session in sessions.sorted(by: { $0.date > $1.date }) {
            let done = Set(session.exercises.map { $0.name.lowercased() })
            var bestIndex: Int?
            var bestScore = 0
            for (i, day) in days.enumerated() {
                let names = Set(day.exercises.map(\.name))
                let overlap = names.intersection(done).count
                // At least half the day's lifts, else it wasn't that day.
                guard overlap * 2 >= names.count, overlap > bestScore else { continue }
                bestScore = overlap
                bestIndex = i
            }
            if let bestIndex { return (bestIndex + 1) % days.count }
        }
        return 0
    }

    /// The last time a lift was logged: its sets and the day, newest first.
    static func lastDone(_ name: String, in sessions: [Session]) -> (entry: ExerciseEntry, day: String)? {
        for session in sessions.sorted(by: { $0.date > $1.date }) {
            if let entry = session.exercises.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return (entry, session.dateString)
            }
        }
        return nil
    }

    /// `squat 3x5 — add 2.5 kg when all sets hit` → name, scheme, note.
    static func parseExercise(_ text: String) -> Exercise? {
        let parts = text.components(separatedBy: " — ")
        let head = parts[0].trimmingCharacters(in: .whitespaces)
        let note = parts.dropFirst().joined(separator: " — ").trimmingCharacters(in: .whitespaces)
        var tokens = head.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return nil }
        let scheme = tokens.removeLast()
        // A scheme has an "x" with something on both sides: 3x5, 3x8-10, 3xAMRAP.
        guard let x = scheme.lowercased().firstIndex(of: "x"),
              x != scheme.startIndex, scheme.index(after: x) != scheme.endIndex,
              Int(scheme[..<x]) != nil else { return nil }
        let name = tokens.joined(separator: " ").lowercased().replacingOccurrences(of: " ", with: "-")
        return Exercise(name: name, scheme: scheme, note: note)
    }
}
