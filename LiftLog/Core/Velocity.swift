import Foundation

/// A set measured by BarVelo, the bar-speed app, handed back to Grepp.
///
/// The handoff is two URLs and nothing else, so neither app needs the other's
/// code, account or container:
///
///     grepp → barvelo://measure?lift=squat&load=100&reps=5&return=grepp
///     barvelo → grepp://velocity?lift=squat&load=100&mcv=0.52,0.50&peak=0.71,0.66&rom=0.68,0.70&date=2026-11-05
///
/// Speeds are mean concentric velocity per rep in m/s, peak in m/s, ROM in
/// metres, in rep order. `load` is absent for a bodyweight lift; `date` is the
/// day the set was lifted, `yyyy-MM-dd`.
///
/// What it becomes is a load and rep count in the Log tab's fields, landed with
/// the usual tap, and at that tap one line in `velocity.md`, beside
/// `training.md` — that file's format is untouched:
///
///     2026-11-05 squat set 3 100x5 mcv 0.52 0.50 0.47 0.45 0.41 loss 21%
///
/// The line names its set the way training.md has it: the day, the lift as the
/// log spells it, which of the day's sets of that lift (counting along the day's
/// lines of it, in order), and the set as logged. So the coach can put the speeds
/// on one set of a 3×5 at the same load. A logged rep count can differ from the
/// speeds (a rep the camera missed); the token is what was logged, the speeds
/// what was measured. Lines from before set numbers, or speeds that arrived with
/// no set to land on, have no `set N`.
struct VelocitySet: Equatable {
    var date: Date
    var lift: String
    var load: Double?
    var mcv: [Double]
    var peak: [Double] = []
    var rom: [Double] = []
    /// Which of the day's sets of this lift it was, from 1. Nil until landed.
    var setNumber: Int?
    /// The set as it went into training.md, when it was landed.
    var logged: WorkSet?

    static let measureScheme = "barvelo"

    var reps: Int { mcv.count }

    /// How much slower the last rep was than the fastest, 0…1. The number
    /// velocity-based training stops a set on.
    var loss: Double? {
        guard let best = mcv.max(), best > 0, let last = mcv.last else { return nil }
        return max(0, (best - last) / best)
    }

    /// The set as `training.md` spells it: `100x5`, `bwx5`. As logged, once landed.
    var token: String { (logged ?? WorkSet(weight: load, added: nil, reps: reps)).token }

    /// This measurement as the set it was landed as: the `number`th set of `lift`
    /// on `date` in training.md, logged as `set`.
    func landed(as set: WorkSet, number: Int, lift: String, on date: Date) -> VelocitySet {
        var v = self
        v.logged = set
        v.setNumber = number
        v.lift = lift
        v.date = date
        v.load = set.weight
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

    /// The `velocity.md` line.
    var line: String {
        var parts = [Session.dateFormatter.string(from: date), lift]
        if let setNumber { parts.append("set \(setNumber)") }
        parts += [token, "mcv " + mcv.map(Self.speed).joined(separator: " ")]
        if let loss { parts.append("loss \(Int((loss * 100).rounded()))%") }
        return parts.joined(separator: " ")
    }

    /// One line for a person: `0.52 → 0.41 m/s · loss 21%`.
    var summary: String {
        guard let first = mcv.first, let last = mcv.last else { return "no reps measured" }
        var text = mcv.count == 1 ? "\(Self.speed(first)) m/s" : "\(Self.speed(first)) → \(Self.speed(last)) m/s"
        if let loss, mcv.count > 1 { text += " · loss \(Int((loss * 100).rounded()))%" }
        return text
    }

    private static func speed(_ v: Double) -> String { String(format: "%.2f", v) }

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

        let load: Double?
        if let raw = value("load"), !raw.isEmpty, raw.lowercased() != "bw" {
            guard let kg = Double(raw), kg > 0 else { return nil }
            load = kg
        } else {
            load = nil
        }

        self.lift = Self.kebab(lift)
        self.load = load
        self.mcv = mcv
        self.peak = peak
        self.rom = rom
        self.date = value("date").flatMap { Session.dateFormatter.date(from: $0) }
            ?? Calendar.current.startOfDay(for: Date())
    }

    init(date: Date, lift: String, load: Double?, mcv: [Double], peak: [Double] = [], rom: [Double] = []) {
        self.date = date; self.lift = lift; self.load = load
        self.mcv = mcv; self.peak = peak; self.rom = rom
    }

    /// The URL that opens BarVelo ready to measure this lift, and to come back.
    static func measureURL(lift: String, load: Double?, reps: Int?) -> URL {
        var c = URLComponents()
        c.scheme = measureScheme
        c.host = "measure"
        var items = [URLQueryItem(name: "lift", value: lift)]
        if let load { items.append(URLQueryItem(name: "load", value: WorkSet.formatWeight(load))) }
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
        let current = file.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = "# Bar speed\n\nOne line per set, measured by BarVelo: the day, the lift, which of the day's sets of it (set 3 = its third set in training.md), the set as logged, mean concentric velocity per rep in m/s, and the last rep's loss against the fastest.\n"
        return (current.isEmpty ? header : current) + "\n" + set.line + "\n"
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
