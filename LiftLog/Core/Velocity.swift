import Foundation

/// A set measured by BarVelo, the bar-velocity app, handed back to Grepp.
///
/// The handoff is two URLs and nothing else, so neither app needs the other's
/// code, account or container. This is contract version 1; BarVelo
/// implements the other side of it identically:
///
///     grepp → barvelo://measure?v=1&lift=squat&load=100&reps=5&return=grepp
///     barvelo → grepp://velocity?v=1&lift=squat&load=100&mcv=0.52,0.50&peak=0.71,0.66&rom=0.68,0.70&date=2026-11-05
///
/// `lift` is Grepp's canonical name for the lift (`bench` goes out as
/// `bench-press`, see `MuscleMap.canonical`), and comes back as it went.
/// Speeds are mean concentric velocity per rep in m/s, peak in m/s, ROM in
/// metres, in rep order. `load` is absent for a bodyweight lift; `added` is
/// there only for a bodyweight lift with load added, in kg (`bw+10`). `date`
/// is the day the set was lifted, `yyyy-MM-dd`. A URL without `v` is from a
/// BarVelo older than versions and reads as 1; a higher `v` is read as far as
/// it goes, and the Log tab says to update Grepp.
///
/// Three fields BarVelo may add, all optional within version 1, so a link
/// without them reads as before. `rir` is BarVelo's estimate of the reps in
/// reserve after the set's last rep, one number from the lifter's own bar-velocity
/// history; `left` is the lifter's own answer to "reps left?" after the set, a
/// count or `fail` for a set that ended on a failed rep; `v1rm` is a 1RM in kg
/// estimated from the lift's load–velocity profile; `scale` is the relative
/// uncertainty of the camera's metres (0.012 = ±1.2%) and `rulers` what they
/// were measured with (`height,plate,rack`), from BarVelo's check of its rulers
/// against each other. Each is extra: one that
/// doesn't read is dropped, never a
/// reason to refuse the speeds.
///
/// What it becomes is a load and rep count in the Log tab's fields, landed with
/// the usual tap. The measurement then rides on that set, by its id, until the
/// lift is finished; at Finish, whether the save went out or was queued
/// offline, each measured set becomes one line in `velocity.md`, beside
/// `training.md` — that file's format is untouched:
///
///     2026-11-05 squat set 3 100x5 mcv 0.52 0.50 0.47 0.45 0.41 loss 21%
///     2026-11-06 over-head-press set 2 42.5x9 mcv 0.78 … 0.41 loss 47% rir ~0 fail v1rm 47.5
///     2026-11-06 squat set 3 110x12 mcv 0.39 … 0.31 loss 23% scale ±1.2% height,plate,rack
///
/// The line names its set the way training.md has it: the day, the lift as the
/// log spells it, which of the day's sets of that lift (counting along the day's
/// lines of it, in order), and the set as logged. So the coach can put the speeds
/// on one set of a 3×5 at the same load. Numbering at Finish rather than at the
/// tap means a set deleted before Finish doesn't leave the others misnumbered,
/// and a lift discarded unfinished leaves no line at all. A logged rep count can
/// differ from the speeds (a rep the camera missed); the token is what was
/// logged, the speeds what was measured. Lines from before set numbers, and
/// speeds that had no set to land on — another lift in hand, or replaced by a
/// newer measurement first — have no `set N`.
///
/// The lines go through `VelocityOutbox`, which keeps them across a relaunch
/// until velocity.md takes them, so a busy sync or no signal never loses one.
struct VelocitySet: Equatable, Codable {
    /// Saved as its day, so a queued line doesn't change day across a flight.
    @DayCoded var date: Date
    var lift: String
    var load: Double?
    /// Load added to a bodyweight lift, kg. Nil without; never set with `load`.
    var added: Double?
    var mcv: [Double]
    var peak: [Double] = []
    var rom: [Double] = []
    /// Which of the day's sets of this lift it was, from 1. Nil until landed.
    var setNumber: Int?
    /// The set as it went into training.md, when it was landed.
    var logged: WorkSet?
    /// The contract version the URL said it spoke; 1 when it didn't say.
    var version: Int = 1
    /// BarVelo's estimate of the reps in reserve after the last rep. Nil
    /// when it sent none.
    var rirEstimate: Double?
    /// The lifter's own answer to "reps left?". Outranks `rirEstimate`.
    var left: Left?
    /// A 1RM in kg estimated from the lift's load–velocity profile.
    var v1rm: Double?
    /// Relative uncertainty of the camera's scale (0.012 = ±1.2%), from how well
    /// BarVelo's rulers agreed. Nil with one ruler, or when it sent none.
    var scale: Double?
    /// What the scale was measured with, most trusted first: `height`, `plate`,
    /// `rack`. Empty when BarVelo sent none.
    var rulers: [String] = []

    /// What the lifter said was left in the tank after the set.
    enum Left: Equatable, Codable {
        /// Could have done this many more.
        case reps(Int)
        /// The set ended on a failed rep.
        case failed

        /// Read `left=`: a count ≥ 0, or `fail`. Nil for anything else.
        init?(_ raw: String) {
            if raw.lowercased() == "fail" { self = .failed; return }
            guard let n = Int(raw), n >= 0 else { return nil }
            self = .reps(n)
        }

        /// As the URL and the velocity.md line spell it: `2` or `fail`.
        var token: String {
            switch self {
            case .reps(let n): return String(n)
            case .failed: return "fail"
            }
        }

        // Saved as its token, so a queued line reads plainly.
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            guard let left = Left(try c.decode(String.self)) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a reps-left answer")
            }
            self = left
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(token)
        }
    }

    /// The version of the handoff this build speaks.
    static let contractVersion = 1
    static let measureScheme = "barvelo"

    var reps: Int { mcv.count }

    /// How much slower the last rep was than the fastest, 0…1. The number
    /// velocity-based training stops a set on.
    var loss: Double? {
        guard let best = mcv.max(), best > 0, let last = mcv.last else { return nil }
        return max(0, (best - last) / best)
    }

    /// How hard the set was, RPE 5…10, as 10 − reps in reserve. From the
    /// lifter's answer when there is one (`fail` is 10), else from BarVelo's
    /// estimate, to the half. Nil with neither.
    var rpe: Double? { Self.rpe(left: left, rirEstimate: rirEstimate) }

    /// The RPE rule on its own, for a set read back from velocity.md too.
    static func rpe(left: Left?, rirEstimate: Double?) -> Double? {
        switch left {
        case .failed: return 10
        case .reps(let n): return Double(max(5, 10 - n))
        case nil:
            guard let rirEstimate else { return nil }
            return min(10, max(5, ((10 - rirEstimate) * 2).rounded() / 2))
        }
    }

    /// The RPE came from BarVelo's estimate, not the lifter's answer.
    var rpeIsEstimated: Bool { left == nil && rpe != nil }

    /// The set as `training.md` spells it: `100x5`, `bwx5`, `bw+10x5`. As
    /// logged, once landed.
    var token: String { (logged ?? WorkSet(weight: load, added: load == nil ? added : nil, reps: reps)).token }

    /// Sent by a BarVelo that speaks a later contract than this Grepp.
    var isFromNewerBarVelo: Bool { version > Self.contractVersion }

    /// This measurement as the set it was landed as: the `number`th set of `lift`
    /// on `date` in training.md, logged as `set`.
    func landed(as set: WorkSet, number: Int, lift: String, on date: Date) -> VelocitySet {
        var v = self
        v.logged = set
        v.setNumber = number
        v.lift = lift
        v.date = date
        v.load = set.weight
        v.added = set.added
        return v
    }

    /// Which set of the day's `lift` the next one landed is, counted the way
    /// training.md lists them: the sets on the day's earlier lines of the lift,
    /// then the line in hand's own (`inHand`, after the new set lands).
    /// `editingOccurrence` is the line being updated (0 = the day's first line of
    /// the lift); nil for a new line, which goes after every other.
    static func setNumber(dayLinesOfLift: [ExerciseEntry], editingOccurrence: Int?, inHand: Int) -> Int {
        let before = editingOccurrence.map { min($0, dayLinesOfLift.count) } ?? dayLinesOfLift.count
        return dayLinesOfLift.prefix(before).reduce(0) { $0 + $1.sets.count } + inHand
    }

    /// A finished lift's measured sets, as velocity.md lines: each measurement
    /// in `measured` (keyed by the id of the set it was landed as) numbered by
    /// where that set sits in `committed`, the line as saved, after the sets on
    /// the day's earlier lines of the lift. A measurement whose set is no longer
    /// in `committed` is not here. In set order.
    static func numbered(_ measured: [UUID: VelocitySet], committed: [WorkSet],
                         dayLinesOfLift: [ExerciseEntry], occurrence: Int?,
                         lift: String, on date: Date) -> [VelocitySet] {
        committed.enumerated().compactMap { index, set in
            measured[set.id].map {
                $0.landed(as: set,
                          number: setNumber(dayLinesOfLift: dayLinesOfLift, editingOccurrence: occurrence, inHand: index + 1),
                          lift: lift, on: date)
            }
        }
    }

    /// The `velocity.md` line.
    var line: String {
        var parts = [Session.dateFormatter.string(from: date), lift]
        if let setNumber { parts.append("set \(setNumber)") }
        parts += [token, "mcv " + mcv.map(Self.speed).joined(separator: " ")]
        if let loss { parts.append("loss \(Int((loss * 100).rounded()))%") }
        // `~`: an estimate, to the whole rep, not a count.
        if let rirEstimate { parts.append("rir ~\(Int(rirEstimate.rounded()))") }
        if let left { parts.append(left == .failed ? "fail" : "left \(left.token)") }
        if let v1rm { parts.append("v1rm " + WorkSet.formatWeight(v1rm)) }
        if let s = Self.scaleToken(scale: scale, rulers: rulers) { parts.append(s) }
        return parts.joined(separator: " ")
    }

    /// One line for a person: `0.52 → 0.41 m/s · loss 21% · RPE 9`, the RPE
    /// `est. RPE 8.5` when it is BarVelo's estimate.
    var summary: String {
        guard let first = mcv.first, let last = mcv.last else { return "no reps measured" }
        var text = mcv.count == 1 ? "\(Self.speed(first)) m/s" : "\(Self.speed(first)) → \(Self.speed(last)) m/s"
        if let loss, mcv.count > 1 { text += " · loss \(Int((loss * 100).rounded()))%" }
        if let rpe { text += " · \(rpeIsEstimated ? "est. " : "")RPE \(Self.tenth(rpe))" }
        return text
    }

    static func speed(_ v: Double) -> String { String(format: "%.2f", v) }

    /// At most one decimal, a whole number without its `.0`: `4.5`, `4`.
    static func tenth(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }

    // MARK: - URLs

    /// Read a `grepp://velocity?…` URL. Nil for anything else, or for one
    /// without a lift or a single measured rep — nothing half-read is logged.
    init?(url: URL) {
        guard url.scheme?.lowercased() == "grepp", url.host?.lowercased() == "velocity",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ key: String) -> String? {
            items.first(where: { $0.name == key })?.value?.trimmingCharacters(in: .whitespaces)
        }
        func numbers(_ key: String) -> [Double]? {
            guard let raw = value(key), !raw.isEmpty else { return [] }
            let parsed = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parsed.allSatisfy({ $0 != nil }) else { return nil }
            return parsed.compactMap { $0 }
        }
        guard let lift = value("lift"), !lift.isEmpty,
              let mcv = numbers("mcv"), !mcv.isEmpty, mcv.allSatisfy({ $0 > 0 && $0 < 10 }),
              let peak = numbers("peak"), let rom = numbers("rom")
        else { return nil }

        // No `v` is a BarVelo from before versions: version 1.
        let version: Int
        if let raw = value("v"), !raw.isEmpty {
            guard let v = Int(raw), v >= 1 else { return nil }
            version = v
        } else {
            version = 1
        }

        let load: Double?
        if let raw = value("load"), !raw.isEmpty, raw.lowercased() != "bw" {
            guard let kg = Double(raw), kg > 0 else { return nil }
            load = kg
        } else {
            load = nil
        }
        // Added load means something only on a bodyweight lift; 0 is none.
        var added: Double?
        if let raw = value("added"), !raw.isEmpty {
            guard let kg = Double(raw), kg >= 0 else { return nil }
            added = kg > 0 && load == nil ? kg : nil
        }

        self.lift = Self.kebab(lift)
        self.load = load
        self.added = added
        self.version = version
        self.mcv = mcv
        self.peak = peak
        self.rom = rom
        self.date = value("date").flatMap { Session.dateFormatter.date(from: $0) }
            ?? Calendar.current.startOfDay(for: Date())

        // The effort fields are extras: one that doesn't read is dropped.
        self.rirEstimate = value("rir").flatMap(Double.init).flatMap { $0 >= 0 && $0.isFinite ? $0 : nil }
        self.left = value("left").flatMap(Left.init)
        self.v1rm = value("v1rm").flatMap(Double.init).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        self.scale = value("scale").flatMap(Double.init).flatMap { $0 >= 0 && $0 < 0.5 ? $0 : nil }
        self.rulers = Self.rulerNames(value("rulers") ?? "")
    }

    /// `scale ±1.2% height,plate,rack`, `scale height`, or nil with neither.
    static func scaleToken(scale: Double?, rulers: [String]) -> String? {
        var t: [String] = []
        if let scale { t.append(String(format: "±%.1f%%", scale * 100)) }
        if !rulers.isEmpty { t.append(rulers.joined(separator: ",")) }
        return t.isEmpty ? nil : "scale " + t.joined(separator: " ")
    }

    /// Ruler names from `height,plate,rack`: lowercase words only, at most four;
    /// anything else is dropped.
    static func rulerNames(_ s: String) -> [String] {
        let names = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0.count <= 12 && $0.allSatisfy { $0.isLetter && $0.isASCII } }
        return Array(names.prefix(4))
    }

    /// Read a saved one. Fields added since the first queued lines may be
    /// missing from an old payload, and read as absent.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _date = try c.decode(DayCoded.self, forKey: .date)
        lift = try c.decode(String.self, forKey: .lift)
        load = try c.decodeIfPresent(Double.self, forKey: .load)
        added = try c.decodeIfPresent(Double.self, forKey: .added)
        mcv = try c.decode([Double].self, forKey: .mcv)
        peak = try c.decodeIfPresent([Double].self, forKey: .peak) ?? []
        rom = try c.decodeIfPresent([Double].self, forKey: .rom) ?? []
        setNumber = try c.decodeIfPresent(Int.self, forKey: .setNumber)
        logged = try c.decodeIfPresent(WorkSet.self, forKey: .logged)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        rirEstimate = try c.decodeIfPresent(Double.self, forKey: .rirEstimate)
        left = try? c.decodeIfPresent(Left.self, forKey: .left)
        v1rm = try c.decodeIfPresent(Double.self, forKey: .v1rm)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale)
        rulers = try c.decodeIfPresent([String].self, forKey: .rulers) ?? []
    }

    init(date: Date, lift: String, load: Double?, added: Double? = nil, mcv: [Double], peak: [Double] = [], rom: [Double] = []) {
        self.date = date; self.lift = lift; self.load = load; self.added = added
        self.mcv = mcv; self.peak = peak; self.rom = rom
    }

    /// The URL that opens BarVelo ready to measure this lift, and to come back.
    /// `lift` should be the canonical name (`MuscleMap.canonical`); `load` nil
    /// for bodyweight, with `added` the load on top of it, if any.
    static func measureURL(lift: String, load: Double?, added: Double? = nil, reps: Int?) -> URL {
        var c = URLComponents()
        c.scheme = measureScheme
        c.host = "measure"
        var items = [URLQueryItem(name: "v", value: String(contractVersion)),
                     URLQueryItem(name: "lift", value: lift)]
        if let load {
            items.append(URLQueryItem(name: "load", value: WorkSet.formatWeight(load)))
        } else if let added, added > 0 {
            items.append(URLQueryItem(name: "added", value: WorkSet.formatWeight(added)))
        }
        if let reps { items.append(URLQueryItem(name: "reps", value: String(reps))) }
        items.append(URLQueryItem(name: "return", value: "grepp"))
        c.queryItems = items
        return c.url!
    }

    /// The log's spelling of a lift: lowercase, words joined by hyphens.
    static func kebab(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
            .joined(separator: "-")
    }

    // MARK: - The file

    /// `velocity.md` with one line added, after what's there.
    static func appending(_ set: VelocitySet, to file: String) -> String {
        appending([set], to: file)
    }

    /// `velocity.md` with these lines added, in order, after what's there. A
    /// line the file already has is not added again: a write that went through
    /// but whose answer was lost is retried, and must not log the set twice.
    /// Speeds to the hundredth on every rep make two real sets one line only
    /// in theory. A file that already has a heading keeps it: files written
    /// before the rename open with `# Bar speed` (backward compatibility),
    /// and nothing here or in `recentLines` reads the heading, only dated lines.
    static func appending(_ sets: [VelocitySet], to file: String) -> String {
        let current = file.trimmingCharacters(in: .whitespacesAndNewlines)
        var present = Set(current.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        let new = sets.map(\.line).filter { present.insert($0).inserted }
        guard !new.isEmpty else { return file }
        let header = "# Bar velocity\n\nOne line per set, measured by BarVelo: the day, the lift, which of the day's sets of it (set 3 = its third set in training.md), the set as logged, mean concentric velocity per rep in m/s, the last rep's loss against the fastest, and, when BarVelo sent them, its estimate of the reps in reserve at the end of the set (rir ~N), the reps the lifter said were left (left N, or fail), a 1RM estimated from bar velocity (v1rm), and how the camera's metres were set (scale ±N% and the rulers: the lifter's height, a plate, the rack).\n"
        return (current.isEmpty ? header : current) + "\n" + new.joined(separator: "\n") + "\n"
    }

    /// The last `limit` measured lines, oldest first, for the coach.
    static func recentLines(_ file: String, limit: Int = 40) -> [String] {
        let lines = file.split(separator: "\n").map(String.init).filter {
            guard let first = $0.split(separator: " ").first else { return false }
            return Session.dateFormatter.date(from: String(first)) != nil
        }
        return Array(lines.suffix(limit))
    }
}

/// The velocity.md lines not yet written, kept until the file takes them.
///
/// A measured set is a few seconds of someone's effort that can't be redone,
/// so its line is never just tried once: it waits here, persisted, through a
/// busy sync, no signal or a relaunch. The Store drains it in one write of
/// everything pending and drops only what that write carried, so a line
/// added during the write waits for the next.
struct VelocityOutbox: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var id = UUID()
        var set: VelocitySet
    }

    private(set) var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// Queue lines, after those waiting. One that reads the same as a line
    /// already waiting is the same set delivered twice, and is not queued.
    mutating func add(_ sets: [VelocitySet]) {
        var waiting = Set(entries.map(\.set.line))
        for set in sets where waiting.insert(set.line).inserted {
            entries.append(Entry(set: set))
        }
    }

    /// The file with every waiting line added.
    func appending(to file: String) -> String {
        VelocitySet.appending(entries.map(\.set), to: file)
    }

    /// Drop what `batch`, an earlier copy of this outbox, wrote. Lines added
    /// since stay.
    mutating func remove(delivered batch: VelocityOutbox) {
        let sent = Set(batch.entries.map(\.id))
        entries.removeAll { sent.contains($0.id) }
    }
}
