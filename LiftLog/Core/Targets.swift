import Foundation

/// A number to hit for a lift, read out of goals.md: "- 140 kg squat by
/// June. Currently 120." or "- bench-press 100 kg by 2026-12-01". The file
/// stays the lifter's own prose; a line counts as a target when it names a
/// lift the log knows and a load in kg (or a count of reps), and the date
/// after "by" is optional. Nothing is written back for it to work.
struct Target: Equatable {
    /// What the number is a number of: a top set in kg, an estimated one-rep
    /// max in kg, or reps. "1RM" anywhere on the line, or in the heading
    /// over it, makes it a max; a count of reps is a count of reps.
    enum Kind: Equatable {
        case topSet, oneRepMax, reps

        var metric: Analytics.Metric {
            switch self {
            case .topSet: return .topSet
            case .oneRepMax: return .oneRepMax
            case .reps: return .maxReps
            }
        }
        var unit: String { self == .reps ? "reps" : "kg" }
        /// "top set", "est. 1RM", "reps" — how the card names the number.
        var label: String {
            switch self {
            case .topSet: return "top set"
            case .oneRepMax: return "est. 1RM"
            case .reps: return "reps"
            }
        }
    }

    /// The canonical lift name.
    let lift: String
    let value: Double
    let kind: Kind
    /// The day it is wanted by, if the line says.
    let by: Date?
    /// The line as written.
    let line: String

    var isReps: Bool { kind == .reps }

    /// "140 kg" / "12 reps".
    var amount: String { kind == .reps ? "\(Int(value)) reps" : "\(WorkSet.formatWeight(value)) kg" }
}

enum Targets {
    /// Every target in the goals file for lifts the log knows, in file
    /// order, one per lift (the first wins). Read the way the file is
    /// written rather than the way a parser would like it: several lifts in
    /// one sentence, a lift as a heading with its number on the lines under
    /// it, a bare number when the sentence is plainly about load, and
    /// "by", "before", "until" or "till" ahead of the date.
    static func parse(_ goals: String, lifts: [String], today: Date = Date(),
                      calendar: Calendar = .current) -> [Target] {
        // Longest names first, so "romanian deadlift" is not read as "deadlift".
        let known = Dictionary(grouping: lifts) { MuscleMap.canonical($0) }
            .keys.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        func lift(in text: String) -> String? {
            // Words only, so "squat:" and "(bench)" are the lifts they name.
            let words = MuscleMap.key(text).map { $0.isLetter || $0.isNumber ? $0 : " " }
            let flat = " " + String(words).split(separator: " ").joined(separator: " ") + " "
            return known.first { flat.contains(" " + $0.replacingOccurrences(of: "-", with: " ") + " ") }
        }

        var out: [Target] = []
        var seen = Set<String>()
        var heading: String?
        // "## 1RM goals": every line under it is a max until the next heading.
        var sectionIsMax = false
        for rawLine in goals.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let isHeading = line.hasPrefix("#") || (line.hasPrefix("**") && line.hasSuffix("**"))
            let text = line.drop { "#-*• ".contains($0) }.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "*: "))
            if isHeading {
                // "## Squat" names the lift for the lines under it; any other
                // heading ends that. "## 1RM goals" makes the section maxes.
                heading = lift(in: text)
                sectionIsMax = isMax(text)
                continue
            }
            // "Squat 140 kg and bench 100 kg by June": one date for the line,
            // one lift and number per clause.
            let lineDate = date(in: text, today: today, calendar: calendar)
            let lineLift = lift(in: text)
            let clauses = split(text, on: clauseBreak)
            let liftsInLine = Set(clauses.compactMap(lift(in:)))
            for clause in clauses where !clause.isEmpty {
                // "Currently 120" is where they are, not where they're going.
                if clause.range(of: #"\b(currently|now|today|at the moment|was|last)\b"#, options: .regularExpression) != nil { continue }
                let name = lift(in: clause) ?? (liftsInLine.count <= 1 ? lineLift : nil) ?? heading
                guard let name, !seen.contains(name), let number = number(in: clause) else { continue }
                seen.insert(name)
                // A clause with its own "by" keeps its own date, readable or
                // not; one without borrows the sentence's.
                let ownDate = clause.range(of: #"\b(by|before|until|till)\b"#, options: .regularExpression) != nil
                let kind: Target.Kind = number.isReps ? .reps
                    : (sectionIsMax || isMax(clause) || isMax(text)) ? .oneRepMax : .topSet
                out.append(Target(lift: name, value: number.value, kind: kind,
                                  by: ownDate ? date(in: clause, today: today, calendar: calendar) : lineDate,
                                  line: line))
            }
        }
        return out
    }

    /// "1RM", "1 RM", "e1RM", "one rep max", "1-rep max", "one-rep maximum".
    static func isMax(_ text: String) -> Bool {
        text.range(of: #"\b(e?1\s*-?\s*rm|(one|1)[\s-]*rep[\s-]*max(imum)?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let clauseBreak = try! NSRegularExpression(pattern: #"\s*(?:[;,]|\band\b|&|\.\s|\.$)\s*"#)

    private static func split(_ text: String, on regex: NSRegularExpression) -> [String] {
        let ns = text as NSString
        var pieces: [String] = []
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            pieces.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        pieces.append(ns.substring(from: last))
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The load the line is about. Every "140 kg", "140kg" or "12 reps" on
    /// it, less the increments — "+5 kg", "add 5 kg", "5 kg a month", "2.5 kg
    /// more" — and of what is left the largest, since a goal outweighs the
    /// steps to it. Failing that, a bare number that reads as a load: 10 to
    /// 500, not part of a 3x5 scheme, not a year, not a percentage or a
    /// count of weeks.
    static func number(in text: String) -> (value: Double, isReps: Bool)? {
        let ns = text as NSString
        var best: (value: Double, isReps: Bool)?
        for m in unitNumber.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let before = ns.substring(to: m.range.location).lowercased()
            let after = ns.substring(from: m.range.location + m.range.length).lowercased()
            if before.range(of: #"(\+|\b(add|adding|another|plus|up|increase|increasing)\s*)\s*$"#, options: .regularExpression) != nil { continue }
            if after.range(of: #"^\s*(more|(per|a|an|each|every)\s+(week|month|session|workout|fortnight))\b"#, options: .regularExpression) != nil { continue }
            let digits = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(digits) else { continue }
            let unit = ns.substring(with: m.range(at: 2)).lowercased()
            let isReps = unit.hasPrefix("rep")
            if best == nil || (isReps == best!.isReps && value > best!.value) || (!isReps && best!.isReps) {
                best = (value, isReps)
            }
        }
        if let best { return best }
        guard let match = text.range(of: #"(?<![\dx.,])(\d+(?:[.,]\d+)?)(?![\dx.,]|\s*(?:%|x|weeks?|days?|months?|sets?|rm\b))"#,
                                     options: .regularExpression) else { return nil }
        let digits = String(text[match]).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(digits), value >= 10, value <= 500 else { return nil }
        return (value, false)
    }

    private static let unitNumber = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*(kg|kilos?|reps?)\b"#, options: .caseInsensitive)

    /// The date after "by", "before", "until" or "till", whichever comes.
    static func date(in text: String, today: Date, calendar: Calendar) -> Date? {
        for word in ["by", "before", "until", "till"] {
            if let d = date(after: word, in: text, today: today, calendar: calendar) { return d }
        }
        return nil
    }

    /// The date after "by": 2026-12-01, 1 Dec 2026, 1 December, December.
    /// Christmas is not a date. A month alone means the end of its next
    /// occurrence; a day and month without a year, its next occurrence.
    /// Month names are read here, not by a formatter, so a bare month or an
    /// odd order parses the same on every locale.
    static func date(after word: String, in text: String, today: Date, calendar: Calendar) -> Date? {
        guard let range = text.range(of: #"\b"# + word + #"\s+([a-z0-9 .\-/]+?)(?:[,;.]|$)"#, options: .regularExpression) else { return nil }
        var phrase = String(text[range]).dropFirst(word.count).trimmingCharacters(in: .whitespaces)
        if phrase.hasSuffix(".") { phrase.removeLast() }
        phrase = phrase.trimmingCharacters(in: .whitespaces)
        if let iso = Session.dateFormatter.date(from: phrase) { return iso }

        var day: Int?, month: Int?, year: Int?
        for token in phrase.split(separator: " ").map(String.init) {
            if let m = monthIndex(token) { month = m; continue }
            // "end of june", "mid march": the words around a month are let by.
            let digits = token.prefix { $0.isNumber }
            guard !digits.isEmpty, let n = Int(digits) else { continue }
            if n > 31 { year = n } else { day = n }
        }
        guard let month else { return nil }
        if let year {
            guard let d = calendar.date(from: DateComponents(year: year, month: month, day: day ?? 1)) else { return nil }
            return day == nil ? endOfMonth(d, calendar) : d
        }
        if let day { return next(month: month, day: day, after: today, calendar: calendar) }
        // A bare month: its end this year while that is still ahead, else next year's.
        var c = calendar.dateComponents([.year], from: today)
        c.month = month; c.day = 1
        let thisYear = endOfMonth(calendar.date(from: c) ?? today, calendar)
        if thisYear >= calendar.startOfDay(for: today) { return thisYear }
        c.year = (c.year ?? 0) + 1
        return endOfMonth(calendar.date(from: c) ?? thisYear, calendar)
    }

    private static let monthNames = ["january", "february", "march", "april", "may", "june", "july",
                                     "august", "september", "october", "november", "december"]

    /// "december", "dec", "sept" → 12, 12, 9.
    private static func monthIndex(_ token: String) -> Int? {
        let word = token.lowercased().filter(\.isLetter)
        guard word.count >= 3 else { return nil }
        return monthNames.firstIndex { $0.hasPrefix(word) || (word.count >= 4 && word.hasPrefix($0.prefix(4))) }.map { $0 + 1 }
    }

    private static func endOfMonth(_ d: Date, _ calendar: Calendar) -> Date {
        let range = calendar.range(of: .day, in: .month, for: d) ?? 1..<29
        var c = calendar.dateComponents([.year, .month], from: d)
        c.day = range.upperBound - 1
        return calendar.date(from: c) ?? d
    }

    private static func next(month: Int, day: Int, after today: Date, calendar: Calendar) -> Date {
        var c = calendar.dateComponents([.year], from: today)
        c.month = month; c.day = day
        let thisYear = calendar.date(from: c) ?? today
        if thisYear >= calendar.startOfDay(for: today) { return thisYear }
        c.year = (c.year ?? 0) + 1
        return calendar.date(from: c) ?? thisYear
    }

    /// "- bench press 100 kg by 1 Dec 2026", "- squat 1RM 140 kg by …" — the
    /// line the app writes when a target is set from Trends, in the shape it reads.
    static func line(lift: String, value: Double, kind: Target.Kind, by: Date?) -> String {
        let name = lift.replacingOccurrences(of: "-", with: " ")
        let amount = kind == .reps ? "\(Int(value)) reps" : "\(WorkSet.formatWeight(value)) kg"
        var text = kind == .oneRepMax ? "- \(name) 1RM \(amount)" : "- \(name) \(amount)"
        if let by {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "d MMM yyyy"
            text += " by \(f.string(from: by))"
        }
        return text
    }
}

/// Where a lift is heading: the slope of its recent sessions carried
/// forward to a target.
struct Projection: Equatable {
    /// The target's value.
    let target: Double
    /// The latest value on the series.
    let current: Double
    /// Gain per day over the recent window; nil or ≤ 0 means no pace to speak of.
    let perDay: Double?
    /// The day the line reaches the target at this pace; nil when it is
    /// already met (`isMet`) or the pace is flat.
    let date: Date?
    var isMet: Bool { current >= target }
}

extension Analytics {
    /// Carry the last twelve weeks of a series forward to `target`. A least
    /// squares line through the points in the window (three at least, else
    /// the last two), from the latest value. Nil with fewer than two points.
    static func projection(_ series: [TrendPoint], to target: Double,
                           now: Date = Date(), calendar: Calendar = .current) -> Projection? {
        guard let last = series.last, series.count >= 2 else { return nil }
        let cutoff = calendar.date(byAdding: .day, value: -84, to: calendar.startOfDay(for: now)) ?? now
        var window = series.filter { $0.date >= cutoff }
        if window.count < 3 { window = Array(series.suffix(2)) }
        guard window.count >= 2, let first = window.first else { return nil }

        let xs = window.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = window.map(\.value)
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for (x, y) in zip(xs, ys) { sxx += (x - mx) * (x - mx); sxy += (x - mx) * (y - my) }
        let slope = sxx > 0 ? sxy / sxx : 0

        if last.value >= target { return Projection(target: target, current: last.value, perDay: slope, date: nil) }
        guard slope > 0 else { return Projection(target: target, current: last.value, perDay: nil, date: nil) }
        let days = (target - last.value) / slope
        let date = last.date.addingTimeInterval(days * 86_400)
        return Projection(target: target, current: last.value, perDay: slope, date: date)
    }
}
