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
        /// The line first: a day can hold the same lift and scheme twice
        /// (a top set and a back-off), and a list needs them apart.
        var id: String { "\(line) \(name) \(scheme)" }
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
        /// The heading's line first: two days can share a title.
        var id: String { "\(line) \(title)" }
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
    /// Headings with nothing under them — a day whose last lift was just
    /// removed, most often. Not days to train, so not in `days`, but kept
    /// so the screen can still show them, to fill or to remove.
    var emptyDays: [Day] = []

    var isEmpty: Bool { days.isEmpty }

    /// Days are headings after the title, or bold lines on their own; lifts are
    /// bullets or numbered lines with a set scheme in them. Written to be lenient:
    /// the coach's output drifts (`### Day 1`, `**Day A**`, `- Squat: 3 x 5`),
    /// and a saved file that shows as empty is worse than a generous read.
    static func parse(_ markdown: String) -> Programme {
        var title = ""
        var days: [Day] = []
        var emptyDays: [Day] = []
        /// The day being read; `level` is its heading's depth (bold lines
        /// deepest), `prose` whether anything but lifts sits under it.
        var current: (title: String, exercises: [Exercise], line: Int, level: Int, prose: Bool)?
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        /// `next` is the depth of the heading that ends the day, if one does.
        func closeDay(at end: Int, next: Int? = nil) {
            if let current {
                let day = Day(title: current.title, exercises: current.exercises, line: current.line, end: end)
                if !current.exercises.isEmpty {
                    days.append(day)
                } else if !current.prose, next.map({ $0 <= current.level }) ?? true {
                    // A bare heading. Not one over a deeper heading, though:
                    // "## Week 1" above "### Day A" groups days, it isn't one.
                    emptyDays.append(day)
                }
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
                    closeDay(at: index, next: level)
                    current = (text, [], index, level, false)
                }
                continue
            }
            // A bold line on its own is a day too: **Day A — Lower**
            if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4, !line.dropFirst(2).dropLast(2).contains("**") {
                closeDay(at: index, next: Int.max)
                current = (String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces), [], index, Int.max, false)
                continue
            }

            if let body = listItem(line), var exercise = parseExercise(body) {
                // Lifts before any heading: a day with no heading line
                // (-1), which a rename gives one and a removal still finds.
                if current == nil { current = ("Session", [], -1, 0, false) }
                exercise.line = index
                current?.exercises.append(exercise)
            } else {
                current?.prose = true
            }
        }
        closeDay(at: lines.count)
        return Programme(title: title, days: days, emptyDays: emptyDays)
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

    /// The set scheme in a line, in the shapes a coach writes it: `3x5`,
    /// `3 x 8–10`, `4×AMRAP`, `2 x max`, `3 sets × 6–10`, `3 sets of 8`,
    /// `3 sets to failure`, `AMRAP x 3`, and `3 sets` with the reps left to
    /// the note ("reps only, add a rep a set"). The first is the file's own
    /// spelling and wins when a line has two; the bare `3 sets` comes last.
    private static let schemes: [NSRegularExpression] = [
        "(\\d+)\\s*(?:sets?\\s*)?(?:[x×]|of)\\s*(\\d+(?:\\s*[-–]\\s*\\d+)?\\+?|amrap|max|failure)",
        "(\\d+)\\s*sets?\\s*(?:to\\s+)?(failure|amrap|max)",
        "(amrap|max)\\s*[x×]\\s*(\\d+)",
        "(\\d+)\\s*(sets?)\\b",
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// `squat 3x5 — add 2.5 kg when all sets hit` → name, scheme, note. Also
    /// `Squat: 3 x 5`, `**Bench press** 3x8-10 (add 2.5 kg)`, `squat 3x5 @ 90 kg`.
    static func parseExercise(_ text: String) -> Exercise? {
        let clean = text.replacingOccurrences(of: "**", with: "")
        let whole = NSRange(clean.startIndex..., in: clean)
        var found: (index: Int, match: NSTextCheckingResult)?
        for (index, regex) in schemes.enumerated() {
            if let m = regex.firstMatch(in: clean, range: whole) { found = (index, m); break }
        }
        guard let found else { return nil }
        let m = found.match
        // The reversed shape, "AMRAP x 3", has its groups the other way round.
        let reversed = found.index == 2
        guard let range = Range(m.range, in: clean),
              let setsRange = Range(m.range(at: reversed ? 2 : 1), in: clean),
              let repsRange = Range(m.range(at: reversed ? 1 : 2), in: clean) else { return nil }

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
        // It may start with a number — "45-degree back extension", "1-arm
        // row" — as long as it's all words and hyphens, so "4 weeks: squat"
        // stays prose.
        guard let first = name.first, name.split(separator: "-").count <= 4,
              first.isLetter || (first.isNumber && name.contains(where: \.isLetter)
                                 && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        else { return nil }

        let reps = clean[repsRange].replacingOccurrences(of: " ", with: "").uppercased()
        // "3 sets" with the reps in the note stays "3 sets": no rep count is
        // not an AMRAP, and the scheme is read back as written.
        let normalised = found.index == 3 ? "\(clean[setsRange]) sets"
            : "\(clean[setsRange])x\(reps == "MAX" || reps == "FAILURE" ? "AMRAP" : reps)"
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
                guard overlap * 2 >= names.count else { continue }
                // Days with the same lifts (a heavy and a light squat day)
                // are told apart by which one's schemes the session fits.
                let score = overlap * 100 + fitting(session, day)
                guard score > bestScore else { continue }
                bestScore = score
                bestIndex = i
            }
            if let bestIndex { return (bestIndex + 1) % days.count }
        }
        return 0
    }

    /// How many of the day's lines the session's entries fit, scheme and all.
    private func fitting(_ session: Session, _ day: Day) -> Int {
        day.exercises.filter { ex in
            session.exercises.contains { MuscleMap.canonical($0.name) == MuscleMap.canonical(ex.name) && LineRule.fits($0, ex) }
        }.count
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
            guard overlap * 2 >= names.count else { continue }
            let score = overlap * 100 + fitting(session, day)
            guard score > bestScore else { continue }
            bestScore = score
            best = day
        }
        return best
    }

    func adherence(in sessions: [Session], weeks: Int = 4, today: Date = Date(),
                   calendar: Calendar = .current) -> Adherence? {
        guard !isEmpty, weeks > 0 else { return nil }
        // Today and the days before it: 28 for four weeks, not 29 — the same
        // weekday four weeks back is the fifth week.
        let start = calendar.date(byAdding: .day, value: -7 * weeks + 1, to: calendar.startOfDay(for: today)) ?? today
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
        let level = headingLevel(md)
        var text = md
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += String(repeating: "#", count: level) + " " + title + "\n"
        for exercise in exercises { text += line(for: exercise) + "\n" }
        return text
    }

    /// The depth of the file's first day heading; 2 when it has none.
    private static func headingLevel(_ md: String) -> Int {
        lines(md).compactMap { raw -> Int? in
            let t = raw.trimmingCharacters(in: .whitespaces)
            let hashes = t.prefix { $0 == "#" }.count
            return hashes >= 2 ? hashes : nil
        }.first ?? 2
    }

    /// The heading with a new title, its marks kept: "## Day A" stays a
    /// second-level heading, "**Day A**" stays bold.
    static func renaming(_ day: Programme.Day, to title: String, in md: String) -> String {
        let all = lines(md)
        // Lifts with no heading over them get one, at the level the file's
        // other days use.
        if day.line < 0, let first = day.exercises.first?.line {
            return inserting(String(repeating: "#", count: headingLevel(md)) + " " + title, at: first, in: md)
        }
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
        // The heading-less day starts at its first lift: the title and
        // prose above it stay.
        let start = day.line >= 0 ? day.line : (day.exercises.first?.line ?? -1)
        guard all.indices.contains(start), day.end > start else { return md }
        all.removeSubrange(start..<min(day.end, all.count))
        // Not two blank lines where the day was.
        if start > 0, start < all.count, all[start].isEmpty, all[start - 1].isEmpty {
            all.remove(at: start)
        }
        return all.joined(separator: "\n")
    }
}

// MARK: - A line's own rule

/// The next session of one programme line, from the rule written on it:
/// "+2.5 kg when the AMRAP hits 10", "+5 kg while it runs past 12", "+2.5 kg
/// once all four sets are clean at 10", "add a rep a set". The last session
/// it reads is the last one that fits the line's scheme, so a heavy squat
/// day follows the last heavy day, not the light one between.
enum LineRule {
    struct Step: Equatable {
        let entry: ExerciseEntry
        let sentence: String
    }

    /// Sets the scheme asks for: `3x8` → 3, `3 sets` → 3.
    static func setCount(_ exercise: Programme.Exercise) -> Int? {
        if let s = exercise.setsAndReps { return s.sets }
        return exercise.scheme.split(separator: " ").first.flatMap { Int($0) }
    }

    /// Whether a logged entry looks like this line: the same number of sets,
    /// and the first set's reps in the scheme's range when it has one.
    static func fits(_ entry: ExerciseEntry, _ exercise: Programme.Exercise) -> Bool {
        guard let count = setCount(exercise), entry.sets.count == count else { return false }
        guard let range = exercise.setsAndReps?.reps, let first = entry.sets.first else { return true }
        return first.reps >= range.lowerBound - 1 && first.reps <= range.upperBound + 2
    }

    /// The newest entry of the lift that fits the line, else the newest at all.
    static func last(_ exercise: Programme.Exercise, in sessions: [Session]) -> (entry: ExerciseEntry, day: String)? {
        var newest: (ExerciseEntry, String)?
        for session in sessions.sorted(by: { $0.date > $1.date }) {
            for entry in Analytics.entries(exercise.name, in: session) where !entry.sets.isEmpty {
                if fits(entry, exercise) { return (entry, session.dateString) }
                if newest == nil { newest = (entry, session.dateString) }
            }
        }
        return newest
    }

    /// One condition on the line: what it adds and when.
    struct Clause: Equatable {
        enum Measure: Equatable { case lastSet, everySet }
        let kg: Double
        let reps: Int
        let measure: Measure
        /// Reps the measured set(s) must reach; nil means the scheme's own.
        let atLeast: Int?
    }

    static func clauses(_ note: String) -> [Clause] {
        let lower = note.lowercased()
        return lower.split(whereSeparator: { $0 == "," || $0 == ";" }).compactMap { raw in
            let c = String(raw)
            let kg = firstMatch(#"\+\s*(\d+(?:\.\d+)?)(?:\s*(?:to|-|–)\s*\d+(?:\.\d+)?)?\s*kg"#, in: c).flatMap(Double.init)
            let addsRep = c.contains("add a rep") || c.contains("+1 rep") || c.contains("a rep a set")
            guard kg != nil || addsRep else { return nil }
            let measure: Clause.Measure = (c.contains("all ") || c.contains("every set") || c.contains("a rep a set")) && !c.contains("top set runs")
                ? .everySet : .lastSet
            var atLeast: Int?
            if let n = firstMatch(#"past\s+(\d+)"#, in: c).flatMap(Int.init) {
                atLeast = n + 1
            } else if let n = firstMatch(#"(?:hits|reaches|clean at|settles at|at)\s+(\d+)"#, in: c).flatMap(Int.init) {
                atLeast = n
            }
            // "add a rep a set, top set AMRAP": no threshold, every time.
            if addsRep && kg == nil { return Clause(kg: 0, reps: 1, measure: .everySet, atLeast: 0) }
            return Clause(kg: kg ?? 0, reps: 0, measure: measure, atLeast: atLeast)
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Today's sets for the line. Nil when the lift isn't in the log, when
    /// it carries added load, or when the line has no rule the app can read
    /// (the caller then falls back to its general rule).
    static func next(_ exercise: Programme.Exercise, in sessions: [Session]) -> Step? {
        guard let (entry, day) = last(exercise, in: sessions), let lastSet = entry.sets.last,
              !entry.sets.contains(where: { ($0.added ?? 0) > 0 }) else { return nil }
        let rules = clauses(exercise.note)
        guard !rules.isEmpty else { return nil }
        let count = setCount(exercise) ?? entry.sets.count
        let schemeReps = exercise.setsAndReps?.reps
        let top = entry.sets.compactMap(\.weight).max()
        let working = top.map { t in entry.sets.filter { $0.weight == t } } ?? entry.sets

        var kgUp = 0.0
        var repUp = 0
        for rule in rules {
            let need = rule.atLeast ?? schemeReps?.lowerBound ?? 0
            let met: Bool
            switch rule.measure {
            case .lastSet: met = lastSet.reps >= need
            case .everySet: met = working.allSatisfy { $0.reps >= need }
            }
            guard met else { continue }
            kgUp = max(kgUp, rule.kg)
            repUp = max(repUp, rule.reps)
        }

        let done = entry.sets.map(\.token).joined(separator: " ")
        let named = readable(exercise.name)
        let sets: [WorkSet]
        let sentence: String
        if let top {
            let kg = top + kgUp
            let reps = schemeReps?.upperBound ?? working.first?.reps ?? lastSet.reps
            sets = Array(repeating: WorkSet(weight: kg, reps: reps), count: count)
            sentence = kgUp > 0
                ? "\(named) up to \(WorkSet.formatWeight(kg)) kg: \(done) on \(day) met its rule."
                : "\(named) at \(WorkSet.formatWeight(kg)) kg again: \(done) on \(day) is short of its rule."
        } else {
            // Bodyweight: last time's reps, set by set, plus what the rule adds.
            var reps = entry.sets.map(\.reps)
            while reps.count < count { reps.append(reps.last ?? 1) }
            reps = Array(reps.prefix(count)).map { $0 + repUp }
            sets = reps.map { WorkSet(weight: nil, reps: $0) }
            sentence = repUp > 0
                ? "\(named): a rep more a set than \(done) on \(day)."
                : "\(named) as on \(day): \(done)."
        }
        return Step(entry: ExerciseEntry(name: entry.name, sets: sets), sentence: sentence)
    }

    private static func readable(_ name: String) -> String {
        let s = MuscleMap.key(name).replacingOccurrences(of: "-", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
