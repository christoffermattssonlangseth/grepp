import Foundation

/// A number to hit for a lift, read out of goals.md: "- 140 kg squat by
/// June. Currently 120." or "- bench-press 100 kg by 2026-12-01". The file
/// stays the lifter's own prose; a line counts as a target when it names a
/// lift the log knows and a load in kg (or a count of reps), and the date
/// after "by" is optional. Nothing is written back for it to work.
struct Target: Equatable {
    /// The canonical lift name.
    let lift: String
    let value: Double
    /// True when the number is a rep count, not a load.
    let isReps: Bool
    /// The day it is wanted by, if the line says.
    let by: Date?
    /// The line as written.
    let line: String
}

enum Targets {
    /// Every target in the goals file for lifts the log knows, in file order.
    static func parse(_ goals: String, lifts: [String], today: Date = Date(),
                      calendar: Calendar = .current) -> [Target] {
        // Longest names first, so "romanian deadlift" is not read as "deadlift".
        let known = Dictionary(grouping: lifts, by: MuscleMap.canonical)
            .keys.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        var out: [Target] = []
        for rawLine in goals.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let text = line.drop { "-*• ".contains($0) }.lowercased()
            let flat = MuscleMap.key(String(text)).replacingOccurrences(of: "-", with: " ")
            guard let lift = known.first(where: { flat.contains($0.replacingOccurrences(of: "-", with: " ")) }) else { continue }
            guard let number = firstNumber(in: String(text)) else { continue }
            out.append(Target(lift: lift, value: number.value, isReps: number.isReps,
                              by: date(after: "by", in: String(text), today: today, calendar: calendar),
                              line: line))
        }
        return out
    }

    /// The first "140 kg" or "12 reps" in a line; "kg" is the default when
    /// a bare number sits before "by". "Currently 120" after the target is
    /// not the target.
    private static func firstNumber(in text: String) -> (value: Double, isReps: Bool)? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(kg|kilos?|reps?)\b"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            let piece = String(text[match])
            let digits = piece.prefix { "0123456789.,".contains($0) }.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(digits) else { return nil }
            return (value, piece.hasSuffix("rep") || piece.hasSuffix("reps"))
        }
        return nil
    }

    /// The date after "by": 2026-12-01, 1 Dec 2026, 1 December, December,
    /// Christmas is not a date. A month alone means the end of its next
    /// occurrence; a day and month without a year, its next occurrence.
    static func date(after word: String, in text: String, today: Date, calendar: Calendar) -> Date? {
        guard let range = text.range(of: #"\b"# + word + #"\s+([a-z0-9 .\-/]+?)(?:[,;.]|$)"#, options: .regularExpression) else { return nil }
        var phrase = String(text[range]).dropFirst(word.count).trimmingCharacters(in: .whitespaces)
        if phrase.hasSuffix(".") { phrase.removeLast() }
        phrase = phrase.trimmingCharacters(in: .whitespaces)
        if let iso = Session.dateFormatter.date(from: phrase) { return iso }
        // The line was lowercased to find the lift; month names go back to
        // their case for the formatter.
        phrase = phrase.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        for format in ["d MMMM yyyy", "d MMM yyyy", "MMMM d yyyy", "MMM d yyyy", "MMMM yyyy", "MMM yyyy"] {
            f.dateFormat = format
            if let d = f.date(from: phrase) {
                return format.hasPrefix("d") || format.contains(" d ") ? d : endOfMonth(d, calendar) }
        }
        // No year: the next time that day or month comes round.
        for format in ["d MMMM", "d MMM", "MMMM d", "MMM d"] {
            f.dateFormat = format
            if let d = f.date(from: phrase) {
                let c = calendar.dateComponents([.month, .day], from: d)
                return next(month: c.month ?? 1, day: c.day ?? 1, after: today, calendar: calendar)
            }
        }
        for format in ["MMMM", "MMM"] {
            f.dateFormat = format
            if let d = f.date(from: phrase) {
                let month = calendar.component(.month, from: d)
                let first = next(month: month, day: 1, after: today, calendar: calendar)
                return endOfMonth(first, calendar)
            }
        }
        return nil
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

    /// "- bench press 100 kg by 1 Dec 2026" — the line the app writes when a
    /// target is set from Trends, in the shape it reads.
    static func line(lift: String, value: Double, isReps: Bool, by: Date?) -> String {
        let name = lift.replacingOccurrences(of: "-", with: " ")
        let amount = isReps ? "\(Int(value)) reps" : "\(WorkSet.formatWeight(value)) kg"
        var text = "- \(name) \(amount)"
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
