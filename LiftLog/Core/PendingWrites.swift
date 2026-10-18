import Foundation

/// One line of the log, pinned down: its day, the lift, the line's text, and
/// which of that day's lines for the lift it is. The same lift can be on a
/// day twice — a back-off line — and an edit, move or delete of one of them
/// must not touch the other.
struct LineRef: Codable, Equatable {
    /// The day, `yyyy-MM-dd`. A ref means nothing on any other day.
    var day: String
    var name: String
    /// The line as it was when it was picked.
    var text: String
    /// 0 for the day's first line of the lift, 1 for the second…
    var occurrence: Int

    init(day: String, name: String, text: String, occurrence: Int) {
        self.day = day
        self.name = name
        self.text = text
        self.occurrence = occurrence
    }

    /// The ref for `entry` as it stands in `session`.
    init(_ entry: ExerciseEntry, in session: Session) {
        day = session.dateString
        name = entry.name
        text = entry.line(date: day)
        let same = session.exercises.filter { Analytics.matches($0.name, entry.name) }
        occurrence = same.firstIndex { $0.id == entry.id } ?? 0
    }

    /// Where the line is among a day's exercises now. Its text first — the
    /// file may have moved under it — and, when the text is gone (changed on
    /// another device), the same-numbered line of the lift. Nil when neither
    /// is there.
    func index(in exercises: [ExerciseEntry]) -> Int? {
        let same = exercises.indices.filter { Analytics.matches(exercises[$0].name, name) }
        let sameText = same.filter { exercises[$0].line(date: day) == text }
        if occurrence < same.count, sameText.contains(same[occurrence]) { return same[occurrence] }
        if let first = sameText.first { return first }
        return occurrence < same.count ? same[occurrence] : nil
    }
}

/// A change that couldn't reach GitHub yet — captured locally so it survives an
/// offline gym session (or a background kill) and replays on the next reconnect.
///
/// It records exactly what the sync path needs to redo the merge-on-write against
/// the then-current remote file: the operation, its day, and the commit message.
struct PendingWrite: Codable, Identifiable, Equatable {
    /// What to do to the given day's session on replay.
    enum Operation: Codable, Equatable {
        case upsert(ExerciseEntry)     // add or replace an exercise
        case delete(name: String)      // remove an exercise (and the day if it empties)
        /// Move one exercise, or the whole day when `name` is nil, to another
        /// day (`yyyy-MM-dd`). Logged on the wrong day, or the morning after.
        case move(name: String?, toDay: String)
        /// Whole sessions added at once — history brought in through the coach.
        /// Each lift merges as if logged on its day; the write's own date is
        /// the newest of them.
        case merge(sessions: [Session])

        static func move(name: String?, to date: Date) -> Operation {
            .move(name: name, toDay: Session.dateFormatter.string(from: date))
        }

        // The shape Swift synthesises for an enum, written out so a move
        // queued before days were kept as text — `to`, an instant — still reads.
        private enum CodingKeys: String, CodingKey { case upsert, delete, move, merge }
        private enum ArgKeys: String, CodingKey { case _0, name, to, toDay, sessions }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if c.contains(.upsert) {
                let a = try c.nestedContainer(keyedBy: ArgKeys.self, forKey: .upsert)
                self = .upsert(try a.decode(ExerciseEntry.self, forKey: ._0))
            } else if c.contains(.delete) {
                let a = try c.nestedContainer(keyedBy: ArgKeys.self, forKey: .delete)
                self = .delete(name: try a.decode(String.self, forKey: .name))
            } else if c.contains(.move) {
                let a = try c.nestedContainer(keyedBy: ArgKeys.self, forKey: .move)
                let name = try a.decodeIfPresent(String.self, forKey: .name)
                if let day = try a.decodeIfPresent(String.self, forKey: .toDay) {
                    self = .move(name: name, toDay: day)
                } else {
                    self = .move(name: name, to: try a.decode(Date.self, forKey: .to))
                }
            } else if c.contains(.merge) {
                let a = try c.nestedContainer(keyedBy: ArgKeys.self, forKey: .merge)
                self = .merge(sessions: try a.decode([Session].self, forKey: .sessions))
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Unknown operation"))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .upsert(let entry):
                var a = c.nestedContainer(keyedBy: ArgKeys.self, forKey: .upsert)
                try a.encode(entry, forKey: ._0)
            case .delete(let name):
                var a = c.nestedContainer(keyedBy: ArgKeys.self, forKey: .delete)
                try a.encode(name, forKey: .name)
            case .move(let name, let day):
                var a = c.nestedContainer(keyedBy: ArgKeys.self, forKey: .move)
                try a.encodeIfPresent(name, forKey: .name)
                try a.encode(day, forKey: .toDay)
            case .merge(let sessions):
                var a = c.nestedContainer(keyedBy: ArgKeys.self, forKey: .merge)
                try a.encode(sessions, forKey: .sessions)
            }
        }
    }

    var id = UUID()
    var operation: Operation
    /// The day the write is for, `yyyy-MM-dd`. Text, not an instant: an
    /// instant re-read after a flight across time zones names another day.
    var day: String
    var message: String
    /// The exact line an upsert replaces, or a delete or one-lift move acts
    /// on. Nil for a fresh log, a whole-day move, and writes queued before
    /// lines were pinned, which act on the lift by name as they always did.
    var target: LineRef?

    /// The day as a date: local midnight of it, wherever the phone is now.
    var date: Date { Session.dateFormatter.date(from: day) ?? Date.distantPast }

    /// Convenience for the common add/replace case.
    init(entry: ExerciseEntry, date: Date, message: String, replacing target: LineRef? = nil) {
        self.init(operation: .upsert(entry), date: date, message: message, target: target)
    }

    init(operation: Operation, date: Date, message: String, target: LineRef? = nil) {
        self.operation = operation
        self.day = Session.dateFormatter.string(from: date)
        self.message = message
        self.target = target
    }

    private enum CodingKeys: String, CodingKey { case id, operation, day, date, message, target }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        operation = try c.decode(Operation.self, forKey: .operation)
        message = try c.decode(String.self, forKey: .message)
        target = try c.decodeIfPresent(LineRef.self, forKey: .target)
        // Queued before days were kept as text: the best that can be done
        // is the day that instant is here.
        if let day = try c.decodeIfPresent(String.self, forKey: .day) {
            self.day = day
        } else {
            self.day = Session.dateFormatter.string(from: try c.decode(Date.self, forKey: .date))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(operation, forKey: .operation)
        try c.encode(day, forKey: .day)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(target, forKey: .target)
    }

    /// The exercise name this write concerns — for showing the queue in the UI.
    var exerciseName: String {
        switch operation {
        case .upsert(let entry): return entry.name
        case .delete(let name): return name
        case .move(let name, _): return name ?? "the day"
        case .merge(let sessions): return "\(sessions.count) \(sessions.count == 1 ? "session" : "sessions")"
        }
    }
}

extension WorkoutParser {

    /// Insert or replace an exercise entry within a session array, keyed by date
    /// + the lift under any of its spellings. Re-logging the same exercise on a
    /// day *replaces* it — that's deliberate: the Session UI treats a second log
    /// as "update this exercise", not a separate block.
    ///
    /// With a `target`, the line replaced is that one and no other — the
    /// second of two squat lines stays the second. A target that's no longer
    /// in the file adds the entry as a line of its own rather than overwrite
    /// a line the lifter didn't pick.
    static func merge(_ entry: ExerciseEntry, on date: Date, replacing target: LineRef? = nil, into base: inout [Session]) {
        merge(entry, onDay: Session.dateFormatter.string(from: date), replacing: target, into: &base)
    }

    static func merge(_ entry: ExerciseEntry, onDay key: String, replacing target: LineRef? = nil, into base: inout [Session]) {
        guard let idx = base.firstIndex(where: { $0.dateString == key }) else {
            guard let date = Session.dateFormatter.date(from: key) else { return }
            base.append(Session(date: date, exercises: [entry]))
            base.sort { $0.date < $1.date }
            return
        }
        let exIdx: Int?
        if let target, target.day == key {
            exIdx = target.index(in: base[idx].exercises)
        } else {
            exIdx = base[idx].exercises.firstIndex { Analytics.matches($0.name, entry.name) }
        }
        if let exIdx {
            base[idx].exercises[exIdx] = keepingNote(entry, from: base[idx].exercises[exIdx])
        } else {
            base[idx].exercises.append(entry)
        }
    }

    /// The new entry with the old line's note, when it brings none of its own:
    /// the Log screen edits sets, and "felt heavy" isn't its to drop.
    private static func keepingNote(_ entry: ExerciseEntry, from old: ExerciseEntry) -> ExerciseEntry {
        var e = entry
        if e.raw == nil, e.note == nil { e.note = old.note }
        return e
    }

    /// Several lines onto one day as one batch: each replaces a same-named
    /// line that was there before, but never one the batch itself just put
    /// there — a day moved with two squat lines arrives with two.
    private static func mergeBatch(_ entries: [ExerciseEntry], onDay key: String, into base: inout [Session]) {
        guard !entries.isEmpty else { return }
        if !base.contains(where: { $0.dateString == key }) {
            guard let date = Session.dateFormatter.date(from: key) else { return }
            base.append(Session(date: date, exercises: []))
            base.sort { $0.date < $1.date }
        }
        guard let idx = base.firstIndex(where: { $0.dateString == key }) else { return }
        let existing = base[idx].exercises.count
        var taken = Set<Int>()
        for entry in entries {
            if let i = (0..<existing).first(where: { !taken.contains($0) && Analytics.matches(base[idx].exercises[$0].name, entry.name) }) {
                base[idx].exercises[i] = entry
                taken.insert(i)
            } else {
                base[idx].exercises.append(entry)
            }
        }
    }

    /// Remove an exercise from a day (case-insensitive). Drops the whole session if
    /// it becomes empty. A no-op if the date or exercise isn't present.
    ///
    /// With a `target`, only that line goes; without one, every line of the
    /// lift — how a delete queued before lines were pinned always behaved.
    static func remove(_ name: String, on date: Date, line target: LineRef? = nil, from base: inout [Session]) {
        remove(name, onDay: Session.dateFormatter.string(from: date), line: target, from: &base)
    }

    static func remove(_ name: String, onDay key: String, line target: LineRef? = nil, from base: inout [Session]) {
        guard let idx = base.firstIndex(where: { $0.dateString == key }) else { return }
        if let target, target.day == key {
            guard let exIdx = target.index(in: base[idx].exercises) else { return }
            base[idx].exercises.remove(at: exIdx)
        } else {
            base[idx].exercises.removeAll { Analytics.matches($0.name, name) }
        }
        if base[idx].exercises.isEmpty { base.remove(at: idx) }
    }

    /// Move an exercise — or every exercise of the day, when `name` is nil —
    /// from one date to another. Merges into the target day like a fresh log
    /// would, so a same-named lift already there is replaced. A no-op when the
    /// dates are the same day or nothing matches.
    ///
    /// With a `line`, only that line moves; two lines of a lift moving
    /// together stay two lines.
    static func move(_ name: String?, on date: Date, line target: LineRef? = nil, to destination: Date, in base: inout [Session]) {
        move(name, onDay: Session.dateFormatter.string(from: date), line: target,
             toDay: Session.dateFormatter.string(from: destination), in: &base)
    }

    static func move(_ name: String?, onDay key: String, line target: LineRef? = nil, toDay destination: String, in base: inout [Session]) {
        guard destination != key,
              let idx = base.firstIndex(where: { $0.dateString == key }) else { return }
        let indices: [Int]
        if name != nil, let target, target.day == key {
            indices = target.index(in: base[idx].exercises).map { [$0] } ?? []
        } else {
            indices = base[idx].exercises.indices.filter { i in
                name.map { Analytics.matches(base[idx].exercises[i].name, $0) } ?? true
            }
        }
        guard !indices.isEmpty else { return }
        // A moved line carries a new date, so it is the app's to write.
        let moving = indices.map { base[idx].exercises[$0].rewritten }
        for i in indices.reversed() { base[idx].exercises.remove(at: i) }
        if base[idx].exercises.isEmpty { base.remove(at: idx) }
        mergeBatch(moving, onDay: destination, into: &base)
    }

    /// Apply one pending write to a session array.
    static func apply(_ write: PendingWrite, to base: inout [Session]) {
        switch write.operation {
        case .upsert(let entry): merge(entry, onDay: write.day, replacing: write.target, into: &base)
        case .delete(let name): remove(name, onDay: write.day, line: write.target, from: &base)
        case .move(let name, let destination):
            move(name, onDay: write.day, line: write.target, toDay: destination, in: &base)
        case .merge(let sessions):
            for session in sessions { mergeBatch(session.exercises, onDay: session.dateString, into: &base) }
        }
    }

    /// Replay a queue of pending writes on top of a base set of sessions, in order.
    /// Used both to show queued-but-unsynced changes in the UI and to reconstruct
    /// state from the local cache while offline.
    static func applying(_ writes: [PendingWrite], to sessions: [Session]) -> [Session] {
        var base = sessions
        for write in writes { apply(write, to: &base) }
        return base
    }
}
