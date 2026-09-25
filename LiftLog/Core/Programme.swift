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
        /// Marked `rpt` on its line: reverse pyramid, loads computed by the
        /// app from the last session rather than asked of the coach.
        var rpt = false
        /// The line of the file it came from, so an edit touches that line
        /// and no other. Not part of equality: a lift is its words.
        var line = -1

        static func == (a: Exercise, b: Exercise) -> Bool {
            a.name == b.name && a.scheme == b.scheme && a.note == b.note && a.rpt == b.rpt
        }

        /// The scheme as numbers, when it has them: `3x4-6` → 3 sets of 4 to 6,
        /// `3x5` → 3 sets of 5. Nil for AMRAP and the like.
        var setsAndReps: (sets: Int, reps: ClosedRange<Int>)? {
            let parts = scheme.split(separator: "x")
            guard parts.count == 2, let sets = Int(parts[0]) else { return nil }
            let reps = parts[1].replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "–", with: "-")
            let bounds = reps.split(separator: "-").compactMap { Int($0) }
            switch bounds.count {
            case 1: return (sets, bounds[0]...bounds[0])
            case 2 where bounds[0] <= bounds[1]: return (sets, bounds[0]...bounds[1])
            default: return nil
            }
        }
    }

    struct Day: Equatable, Identifiable {
        var id: String { title }
        let title: String
        let exercises: [Exercise]
        /// The heading's line, and the line after the day's last: the block
        /// an edit of the day may touch. Not part of equality.
        var line = -1
        var end = -1

        static func == (a: Day, b: Day) -> Bool { a.title == b.title && a.exercises == b.exercises }
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
        var current: (title: String, exercises: [Exercise], line: Int)?
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        func closeDay(at end: Int) {
            if let current, !current.exercises.isEmpty {
                days.append(Day(title: current.title, exercises: current.exercises, line: current.line, end: end))
            }
            current = nil
        }

        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                let level = line.prefix { $0 == "#" }.count
                if level == 1 && title.isEmpty && days.isEmpty && current == nil {
                    title = text
                } else if !text.isEmpty {
                    closeDay(at: index)
                    current = (text, [], index)
                }
                continue
            }
            // A bold line on its own is a day too: **Day A — Lower**
            if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4, !line.dropFirst(2).dropLast(2).contains("**") {
                closeDay(at: index)
                current = (String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces), [], index)
                continue
            }

            if let body = listItem(line), var exercise = parseExercise(body) {
                if current == nil { current = ("Session", [], -1) }
                exercise.line = index
                current?.exercises.append(exercise)
            }
        }
        closeDay(at: lines.count)
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

        // `rpt` marks the scheme when it sits with the name or right after the
        // scheme — not anywhere in a note, and not in a sentence that happens
        // to mention it.
        var head = String(clean[..<range.lowerBound])
        var tail = String(clean[range.upperBound...])
        var rpt = false
        if rptWord.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)) != nil {
            rpt = true
            head = rptWord.stringByReplacingMatches(in: head, options: [], range: NSRange(head.startIndex..., in: head), withTemplate: " ")
        }
        let tailTrimmed = tail.trimmingCharacters(in: .whitespaces)
        if tailTrimmed.lowercased().hasPrefix("rpt"), tailTrimmed.dropFirst(3).first.map({ !$0.isLetter }) ?? true {
            rpt = true
            tail = String(tailTrimmed.dropFirst(3))
        }

        let name = head
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":—–-,"))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        // A lift's name is a few words; a sentence with a scheme in it is prose.
        guard !name.isEmpty, name.first!.isLetter, name.split(separator: "-").count <= 4 else { return nil }

        let reps = clean[repsRange].replacingOccurrences(of: " ", with: "").uppercased()
        let normalised = "\(clean[setsRange])x\(reps == "MAX" ? "AMRAP" : reps)"
        let note = tail
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":—–-,("))
            .trimmingCharacters(in: CharacterSet(charactersIn: ") "))
        return Exercise(name: name, scheme: normalised, note: note, rpt: rpt)
    }

    private static let rptWord = try! NSRegularExpression(pattern: "(?<![a-z])rpt(?![a-z])", options: [.caseInsensitive])

    // MARK: - Against the log

    /// Which day comes next: the one after the day most recently done, judged
    /// by which day's lifts a session covered best. The first day when nothing
    /// in the log matches any day, or when the programme has one day.
    func dueDayIndex(in sessions: [Session]) -> Int {
        guard days.count > 1 else { return 0 }
        for session in sessions.sorted(by: { $0.date > $1.date }) {
            let done = Set(session.exercises.map { MuscleMap.canonical($0.name) })
            var bestIndex: Int?
            var bestScore = 0
            for (i, day) in days.enumerated() {
                let names = Set(day.exercises.map { MuscleMap.canonical($0.name) })
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
    /// How the last weeks went against the file: sessions that were one of
    /// its days, and the lifts left out of those days most often.
    struct Adherence: Equatable {
        struct Skip: Equatable, Identifiable {
            var id: String { name }
            let name: String
            /// Days the lift's day was done without it, and days it was due.
            let missed: Int
            let due: Int
        }
        let weeks: Int
        /// Sessions in the window that were a programme day.
        let daysDone: Int
        /// Sessions in the window that were none of the days.
        let other: Int
        let skipped: [Skip]

        var perWeek: Double { Double(daysDone) / Double(max(1, weeks)) }
    }

    /// A session is a programme day when at least half the day's lifts are
    /// in it, the same rule that picks the day that is next.
    func day(matching session: Session) -> Day? {
        let done = Set(session.exercises.map { MuscleMap.canonical($0.name) })
        var best: Day?
        var bestScore = 0
        for day in days {
            let names = Set(day.exercises.map { MuscleMap.canonical($0.name) })
            let overlap = names.intersection(done).count
            guard overlap * 2 >= names.count, overlap > bestScore else { continue }
            bestScore = overlap
            best = day
        }
        return best
    }

    func adherence(in sessions: [Session], weeks: Int = 4, today: Date = Date(),
                   calendar: Calendar = .current) -> Adherence? {
        guard !isEmpty, weeks > 0 else { return nil }
        let start = calendar.date(byAdding: .day, value: -7 * weeks, to: calendar.startOfDay(for: today)) ?? today
        var daysDone = 0
        var other = 0
        var missed: [String: Int] = [:]
        var due: [String: Int] = [:]
        var order: [String] = []
        for session in sessions where session.date >= start && session.date <= today {
            guard let day = day(matching: session) else { other += 1; continue }
            daysDone += 1
            let done = Set(session.exercises.map { MuscleMap.canonical($0.name) })
            for exercise in day.exercises {
                let key = MuscleMap.canonical(exercise.name)
                if due[key] == nil { order.append(key) }
                due[key, default: 0] += 1
                if !done.contains(key) { missed[key, default: 0] += 1 }
            }
        }
        let skipped = order.compactMap { key -> Adherence.Skip? in
            guard let m = missed[key], m > 0 else { return nil }
            return Adherence.Skip(name: key, missed: m, due: due[key] ?? m)
        }
        .sorted { $0.missed != $1.missed ? $0.missed > $1.missed : $0.name < $1.name }
        return Adherence(weeks: weeks, daysDone: daysDone, other: other, skipped: skipped)
    }

    static func lastDone(_ name: String, in sessions: [Session]) -> (entry: ExerciseEntry, day: String)? {
        for session in sessions.sorted(by: { $0.date > $1.date }) {
            if let entry = Analytics.entries(name, in: session).first {
                return (entry, session.dateString)
            }
        }
        return nil
    }

}

// MARK: - Editing the file

/// Edits to program.md that touch the lines they mean to and no others:
/// the coach's prose between the days, a note under a heading, the title,
/// all come back byte for byte. Every edit takes the file and gives the
/// file; the screen keeps a draft and saves it once.
enum ProgrammeText {
    /// The line a lift is written as: "- squat rpt 3x5 — add 2.5 kg when
    /// all sets hit", in the shape the parser reads.
    static func line(for exercise: Programme.Exercise) -> String {
        var text = "- \(exercise.name)"
        if exercise.rpt { text += " rpt" }
        text += " \(exercise.scheme)"
        if !exercise.note.isEmpty { text += " — \(exercise.note)" }
        return text
    }

    private static func lines(_ md: String) -> [String] {
        md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    static func replacing(line index: Int, with text: String, in md: String) -> String {
        var all = lines(md)
        guard all.indices.contains(index) else { return md }
        all[index] = text
        return all.joined(separator: "\n")
    }

    static func removing(line index: Int, in md: String) -> String {
        var all = lines(md)
        guard all.indices.contains(index) else { return md }
        all.remove(at: index)
        return all.joined(separator: "\n")
    }

    static func inserting(_ text: String, at index: Int, in md: String) -> String {
        var all = lines(md)
        let at = min(max(0, index), all.count)
        all.insert(text, at: at)
        return all.joined(separator: "\n")
    }

    /// A lift added to a day: after its last lift, or straight under the
    /// heading of a day with none.
    static func adding(_ exercise: Programme.Exercise, to day: Programme.Day, in md: String) -> String {
        let after = day.exercises.last?.line ?? day.line
        return inserting(line(for: exercise), at: after + 1, in: md)
    }

    /// The day's lifts in a new order, written back over the same lines, so
    /// a note between two lifts stays where it was.
    static func reordering(_ day: Programme.Day, to order: [Programme.Exercise], in md: String) -> String {
        let slots = day.exercises.map(\.line).sorted()
        guard slots.count == order.count else { return md }
        var all = lines(md)
        for (slot, exercise) in zip(slots, order) {
            guard all.indices.contains(slot), all.indices.contains(exercise.line) else { return md }
        }
        let texts = order.map { lines(md)[$0.line] }
        for (slot, text) in zip(slots, texts) { all[slot] = text }
        return all.joined(separator: "\n")
    }

    /// A new day at the end of the file, its heading at the level the file
    /// uses, with its first lifts.
    static func appendingDay(_ title: String, exercises: [Programme.Exercise], to md: String) -> String {
        let level = lines(md).compactMap { raw -> Int? in
            let t = raw.trimmingCharacters(in: .whitespaces)
            let hashes = t.prefix { $0 == "#" }.count
            return hashes >= 2 ? hashes : nil
        }.first ?? 2
        var text = md
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += String(repeating: "#", count: level) + " " + title + "\n"
        for exercise in exercises { text += line(for: exercise) + "\n" }
        return text
    }

    /// The heading with a new title, its marks kept: "## Day A" stays a
    /// second-level heading, "**Day A**" stays bold.
    static func renaming(_ day: Programme.Day, to title: String, in md: String) -> String {
        let all = lines(md)
        guard all.indices.contains(day.line) else { return md }
        let raw = all[day.line]
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let text: String
        if trimmed.hasPrefix("#") {
            text = String(trimmed.prefix { $0 == "#" }) + " " + title
        } else {
            text = "**" + title + "**"
        }
        return replacing(line: day.line, with: text, in: md)
    }

    /// The day gone: its heading, its lifts and whatever sits between them
    /// up to the next heading. The days after it are untouched.
    static func removing(_ day: Programme.Day, from md: String) -> String {
        var all = lines(md)
        guard all.indices.contains(day.line), day.end > day.line else { return md }
        all.removeSubrange(day.line..<min(day.end, all.count))
        // Not two blank lines where the day was.
        if day.line > 0, day.line < all.count, all[day.line].isEmpty, all[day.line - 1].isEmpty {
            all.remove(at: day.line)
        }
        return all.joined(separator: "\n")
    }
}
