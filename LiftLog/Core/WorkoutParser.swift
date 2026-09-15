import Foundation

/// Reads and writes the plain-text `training.md` format:
///
///     2026-08-30 deadlift 82.5x8 82.5x8 82.5x8
///     2026-08-30 chin-ups bwx6 bwx6 bwx6
///
/// Lines for the same date are grouped into one Session. Blank lines separate dates.
enum WorkoutParser {

    static func parse(_ text: String) -> [Session] {
        var byDate: [String: Session] = [:]
        var order: [String] = []

        for line in lines(of: text) {
            if line.isEmpty { continue }
            guard let parsed = parseLine(line) else { continue }
            let (dateKey, date, entry) = parsed
            if byDate[dateKey] == nil {
                byDate[dateKey] = Session(date: date, exercises: [entry])
                order.append(dateKey)
            } else {
                byDate[dateKey]?.exercises.append(entry)
            }
        }

        return order.compactMap { byDate[$0] }
            .sorted { $0.date < $1.date }
    }

    /// Parse a single token like "46.5x8", "bwx3" or "bw+5x8".
    /// The file's lines, trimmed, with a Windows line ending or a byte-order
    /// mark stripped rather than left to poison the last token of every line.
    static func lines(of text: String) -> [String] {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // "\r\n" is one Character to Swift, so a split on "\n" would never
        // find it: normalise the endings first.
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// One line as (day key, its date, the entry) — or nil when it isn't a log
    /// line. The name is every token before the first set, joined with "-",
    /// so `bench press 60x5` is the lift `bench-press`, not `bench` with a
    /// dropped token.
    static func parseLine(_ line: String) -> (String, Date, ExerciseEntry)? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 3, let date = Session.dateFormatter.date(from: tokens[0]) else { return nil }
        // A closure rather than `compactMap(parseSet)`: passing the method as a
        // function value strips it of the caller's actor isolation, which the
        // app target (MainActor by default) rejects.
        guard let firstSet = tokens.indices.dropFirst(2).first(where: { parseSet(tokens[$0]) != nil }) else { return nil }
        // The file's own casing is kept: a rewrite must not change a line it
        // didn't mean to touch.
        let name = tokens[1..<firstSet].joined(separator: "-")
        let sets = tokens[firstSet...].compactMap { parseSet($0) }
        guard !name.isEmpty, !sets.isEmpty else { return nil }
        return (tokens[0], date, ExerciseEntry(name: name, sets: sets))
    }

    /// Non-blank lines the parser would drop, with their 1-based numbers. A
    /// save rewrites the file from what was parsed, so these must be known
    /// before anything is written — a line that can't be read must not be
    /// silently deleted.
    static func unreadableLines(in text: String) -> [(number: Int, text: String)] {
        lines(of: text).enumerated().compactMap { i, line -> (number: Int, text: String)? in
            line.isEmpty || parseLine(line) != nil ? nil : (number: i + 1, text: line)
        }
    }

    static func parseSet(_ token: String) -> WorkSet? {
        let parts = token.lowercased().split(separator: "x")
        // A rep count is a positive whole number: "100x-5" and "100x0" are typos
        // to be named as unreadable, not sets to be charted.
        guard parts.count == 2, let reps = Int(parts[1]), reps > 0 else { return nil }
        let load = parts[0]
        if load == "bw" {
            return WorkSet(weight: nil, added: nil, reps: reps)
        }
        if load.hasPrefix("bw+") {
            guard let added = Double(load.dropFirst(3)) else { return nil }
            return WorkSet(weight: nil, added: added, reps: reps)
        }
        guard let weight = Double(load) else { return nil }
        return WorkSet(weight: weight, added: nil, reps: reps)
    }

    /// Serialize sessions back to the file format (ascending date, blank line between dates).
    static func serialize(_ sessions: [Session]) -> String {
        sessions
            .sorted { $0.date < $1.date }
            .map { session in
                session.exercises
                    .map { $0.line(date: session.dateString) }
                    .joined(separator: "\n")
            }
            .joined(separator: "\n\n") + "\n"
    }

    /// Most recent prior entry for an exercise, for "last time" suggestions.
    static func lastEntry(for name: String, in sessions: [Session], before date: Date) -> ExerciseEntry? {
        sessions
            .filter { $0.date < date }
            .sorted { $0.date > $1.date }
            .compactMap { s in s.exercises.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
            .first
    }
}
