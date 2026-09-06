import Foundation

/// One set within an exercise.
///
/// Three shapes of load, matching the training.md tokens:
/// - absolute barbell load — `weight` set, `added` nil       → "82.5x8"
/// - pure bodyweight        — `weight` nil, `added` nil/0     → "bwx8"
/// - bodyweight + extra load — `weight` nil, `added` > 0      → "bw+5x8"
struct WorkSet: Identifiable, Equatable, Codable {
    var id = UUID()
    var weight: Double?   // absolute load; nil => a bodyweight movement
    var added: Double?    // extra load on a bodyweight movement (bw+X); nil/0 => none
    var reps: Int

    /// True for any bodyweight-based movement, whether or not weight is added.
    var isBodyweight: Bool { weight == nil }

    /// Serialize to the training.md token, e.g. "46.5x8", "bwx3" or "bw+5x8".
    var token: String {
        let load: String
        if let weight {
            load = WorkSet.formatWeight(weight)
        } else if let added, added > 0 {
            load = "bw+\(WorkSet.formatWeight(added))"
        } else {
            load = "bw"
        }
        return "\(load)x\(reps)"
    }

    /// The load as a person says it: "87.5 kg", "BW +5 kg", "Bodyweight".
    var loadLabel: String {
        if let weight { return "\(WorkSet.formatWeight(weight)) kg" }
        if let added, added > 0 { return "BW +\(WorkSet.formatWeight(added)) kg" }
        return "Bodyweight"
    }

    static func formatWeight(_ w: Double) -> String {
        if w == w.rounded() { return String(Int(w)) }
        // Gym plates step in fractions of a kg; one decimal is plenty and keeps the
        // token clean (no "82.50000001"). Always "." — never a locale comma.
        return String(format: "%.1f", w)
    }
}

/// One exercise line: a name plus its sets.
struct ExerciseEntry: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var sets: [WorkSet]

    func line(date: String) -> String {
        let setStr = sets.map(\.token).joined(separator: " ")
        return "\(date) \(name) \(setStr)"
    }
}

/// All the exercises logged on one calendar date.
struct Session: Identifiable, Equatable, Codable {
    var id = UUID()
    var date: Date
    var exercises: [ExerciseEntry]

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var dateString: String { Session.dateFormatter.string(from: date) }
}
