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

    /// Two sets are the same set when they read the same; the id is for lists.
    /// Every parse mints new ids, and a log that compared by id was never equal
    /// to itself, so every reload redrew everything.
    static func == (a: WorkSet, b: WorkSet) -> Bool {
        a.weight == b.weight && a.added == b.added && a.reps == b.reps
    }

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
    /// The line exactly as the file had it, when this entry was read from the
    /// file rather than made in the app. Written back untouched: a save never
    /// re-spells, re-cases or re-spaces a line it didn't mean to change.
    var raw: String? = nil

    func line(date: String) -> String {
        if let raw { return raw }
        let setStr = sets.map(\.token).joined(separator: " ")
        return "\(date) \(name) \(setStr)"
    }

    /// The same entry as something the app is writing: no line to keep.
    var rewritten: ExerciseEntry { var e = self; e.raw = nil; return e }

    static func == (a: ExerciseEntry, b: ExerciseEntry) -> Bool {
        a.name == b.name && a.sets == b.sets && a.raw == b.raw
    }
}

/// All the exercises logged on one calendar date.
struct Session: Identifiable, Equatable, Codable {
    var id = UUID()
    var date: Date
    var exercises: [ExerciseEntry]

    /// The log's date, `yyyy-MM-dd`, in the phone's own time zone — so a set
    /// landed at 01:00 in Stockholm or 19:00 in Los Angeles is filed under the
    /// day the lifter would name, and every "is this today" check in the app
    /// (all on `Calendar.current`) agrees with the key in the file. A parsed
    /// date is local midnight of its day.
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// A calendar in the same zone as the file's dates, for day arithmetic.
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = dateFormatter.timeZone
        return c
    }

    var dateString: String { Session.dateFormatter.string(from: date) }

    static func == (a: Session, b: Session) -> Bool {
        a.date == b.date && a.exercises == b.exercises
    }
}
