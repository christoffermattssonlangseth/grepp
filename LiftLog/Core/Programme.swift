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

    /// Days are headings after the title, or bold lines on their own; lifts are
    /// bullets or numbered lines with a set scheme in them. Written to be lenient:
    /// the coach's output drifts (`### Day 1`, `**Day A**`, `- Squat: 3 x 5`),
    /// and a saved file that shows as empty is worse than a generous read.
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
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                let level = line.prefix { $0 == "#" }.count
                if level == 1 && title.isEmpty && days.isEmpty && current == nil {
                    title = text
                } else if !text.isEmpty {
                    closeDay()
                    current = (text, [])
                }
                continue
            }
            // A bold line on its own is a day too: **Day A — Lower**
            if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4, !line.dropFirst(2).dropLast(2).contains("**") {
                closeDay()
                current = (String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces), [])
                continue
            }

            if let body = listItem(line), let exercise = parseExercise(body) {
                if current == nil { current = ("Session", []) }
                current?.exercises.append(exercise)
            }
        }
        closeDay()
        return Programme(title: title, days: days)
    }

    /// The text of a `- `, `* ` or `1. ` line; nil for anything else.
    private static func listItem(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return String(line.dropFirst(2))
        }
        if let dot = line.firstIndex(of: "."), Int(line[..<dot]) != nil, line[dot...].hasPrefix(". ") {
            return String(line[line.index(dot, offsetBy: 2)...])
        }
        return nil
    }

    /// The set scheme in a line: `3x5`, `3 x 8–10`, `4×AMRAP`, `2 x max`.
    private static let scheme = try! NSRegularExpression(
        pattern: "(\\d+)\\s*[x×]\\s*(\\d+(?:\\s*[-–]\\s*\\d+)?\\+?|amrap|max)",
        options: [.caseInsensitive])

    /// `squat 3x5 — add 2.5 kg when all sets hit` → name, scheme, note. Also
    /// `Squat: 3 x 5`, `**Bench press** 3x8-10 (add 2.5 kg)`, `squat 3x5 @ 90 kg`.
    static func parseExercise(_ text: String) -> Exercise? {
        let clean = text.replacingOccurrences(of: "**", with: "")
        let whole = NSRange(clean.startIndex..., in: clean)
        guard let m = scheme.firstMatch(in: clean, range: whole),
              let range = Range(m.range, in: clean),
              let setsRange = Range(m.range(at: 1), in: clean),
              let repsRange = Range(m.range(at: 2), in: clean) else { return nil }

        let name = clean[..<range.lowerBound]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":—–-,"))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !name.isEmpty, name.first!.isLetter else { return nil }

        let reps = clean[repsRange].replacingOccurrences(of: " ", with: "").uppercased()
        let normalised = "\(clean[setsRange])x\(reps == "MAX" ? "AMRAP" : reps)"
        let note = clean[range.upperBound...]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":—–-,("))
            .trimmingCharacters(in: CharacterSet(charactersIn: ") "))
        return Exercise(name: name, scheme: normalised, note: note)
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

}
