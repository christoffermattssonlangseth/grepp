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

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let tokens = line.split(separator: " ").map(String.init)
            guard tokens.count >= 3,
                  let date = Session.dateFormatter.date(from: tokens[0]) else { continue }

            let dateKey = tokens[0]
            let name = tokens[1]
            // A closure rather than `compactMap(parseSet)`: passing the method as a
            // function value strips it of the caller's actor isolation, which the
            // app target (MainActor by default) rejects. This compiles the same in
            // the Foundation-only package target.
            let sets = tokens[2...].compactMap { parseSet($0) }
            guard !sets.isEmpty else { continue }

            let entry = ExerciseEntry(name: name, sets: sets)
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
    static func parseSet(_ token: String) -> WorkSet? {
        let parts = token.lowercased().split(separator: "x")
        guard parts.count == 2, let reps = Int(parts[1]) else { return nil }
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
