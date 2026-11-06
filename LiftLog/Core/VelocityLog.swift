import Foundation

/// One line of `velocity.md`, read back: a set BarVelo measured, as Trends
/// draws it.
///
///     2026-10-06 squat set 3 110x12 mcv 0.39 0.41 … 0.32 loss 24% rir ~1 fail v1rm 128
///
/// The day, the lift as the log spells it, `set N` when the line has one, the
/// set as logged, `mcv` and a speed per rep in m/s; then, each optional, `loss
/// N%`, `rir ~N`, `left N` or `fail`, `v1rm X`, `scale ±N% rulers`. A line without a day, a lift,
/// a set or a single speed is not a measurement and is skipped; a token after
/// the speeds that doesn't read is dropped, the way the URL's extras are.
struct VelocityRecord: Equatable {
    var date: Date
    var lift: String
    /// Which of the day's sets of the lift, from 1. Nil on older lines.
    var setNumber: Int?
    /// The set as logged: its load (nil weight for bodyweight, `added` for
    /// `bw+10`) and its reps.
    var logged: WorkSet
    var mcv: [Double]
    /// The loss the line states, 0…1; computed from the speeds without one.
    var loss: Double?
    var rirEstimate: Double?
    var left: VelocitySet.Left?
    var v1rm: Double?
    /// The scale's relative uncertainty and the rulers it came from, when stated.
    var scale: Double?
    var rulers: [String] = []

    /// Load in kg; nil for a bodyweight lift.
    var load: Double? { logged.weight }
    /// Load added to a bodyweight lift, kg; nil without.
    var added: Double? { logged.weight == nil && (logged.added ?? 0) > 0 ? logged.added : nil }
    /// Reps as logged, which can differ from the speeds measured.
    var reps: Int { logged.reps }

    /// The fastest rep.
    var best: Double { mcv.max() ?? 0 }
    /// The last rep.
    var lastRep: Double { mcv.last ?? 0 }

    /// RPE by the same rules as `VelocitySet.rpe`.
    var rpe: Double? { VelocitySet.rpe(left: left, rirEstimate: rirEstimate) }
    var rpeIsEstimated: Bool { left == nil && rpe != nil }

    /// How hard it was, shortest: `fail`, `RPE 9`, `est. RPE 8.5`; nil with no
    /// effort on the line.
    var effort: String? {
        if left == .failed { return "fail" }
        guard let rpe else { return nil }
        return "\(rpeIsEstimated ? "est. " : "")RPE \(VelocitySet.tenth(rpe))"
    }

    /// One row of the list, without the day:
    /// `set 3 · 110×12 · 0.42 → 0.32 m/s · −24% · fail`.
    var detail: String {
        var parts: [String] = []
        if let setNumber { parts.append("set \(setNumber)") }
        parts.append(logged.token.replacingOccurrences(of: "x", with: "×"))
        parts.append(mcv.count == 1 ? "\(VelocitySet.speed(best)) m/s"
                                    : "\(VelocitySet.speed(best)) → \(VelocitySet.speed(lastRep)) m/s")
        if let loss, mcv.count > 1 { parts.append("−\(Int((loss * 100).rounded()))%") }
        if let effort { parts.append(effort) }
        return parts.joined(separator: " · ")
    }

    /// The load as a person says it, for the comparison: `110 kg`,
    /// `bodyweight`, `bw +10 kg`.
    var loadLabel: String {
        if let load { return "\(WorkSet.formatWeight(load)) kg" }
        if let added { return "bw +\(WorkSet.formatWeight(added)) kg" }
        return "bodyweight"
    }

    /// Two sets at the same load, to the hundredth of a kilo; bodyweight
    /// matches bodyweight with the same added load.
    func sameLoad(as other: VelocityRecord) -> Bool {
        switch (load, other.load) {
        case let (a?, b?): return abs(a - b) <= 0.01 + 1e-9
        case (nil, nil): return abs((added ?? 0) - (other.added ?? 0)) <= 0.01 + 1e-9
        default: return false
        }
    }

    // MARK: - Reading

    /// Read one line. Nil for anything that isn't a measured set.
    init?(line raw: String) {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 4, let date = Session.dateFormatter.date(from: tokens[0]) else { return nil }

        // The lift runs up to `set N` or the set token, so a log name with a
        // space in it still reads.
        var i = 1
        var name: [String] = []
        var setNumber: Int?
        var logged: WorkSet?
        while i < tokens.count {
            let t = tokens[i]
            if t.lowercased() == "set", i + 1 < tokens.count, let n = Int(tokens[i + 1]), n >= 1,
               let s = WorkoutParser.parseSet(tokens[safe: i + 2] ?? "") {
                setNumber = n; logged = s; i += 3; break
            }
            if let s = WorkoutParser.parseSet(t) { logged = s; i += 1; break }
            if t.lowercased() == "mcv" { return nil }
            name.append(t)
            i += 1
        }
        guard !name.isEmpty, let logged, i < tokens.count, tokens[i].lowercased() == "mcv" else { return nil }
        i += 1

        var mcv: [Double] = []
        while i < tokens.count, let v = Double(tokens[i]) {
            guard v > 0, v < 10 else { return nil }
            mcv.append(v)
            i += 1
        }
        guard !mcv.isEmpty else { return nil }

        var loss: Double?
        var rir: Double?
        var left: VelocitySet.Left?
        var v1rm: Double?
        var scale: Double?
        var rulers: [String] = []
        while i < tokens.count {
            let key = tokens[i].lowercased()
            let value = tokens[safe: i + 1]
            switch key {
            case "loss":
                if let v = value.flatMap({ Double($0.replacingOccurrences(of: "%", with: "")) }), v >= 0, v <= 100 {
                    loss = v / 100; i += 1
                }
            case "rir":
                if let v = value.flatMap({ Double($0.replacingOccurrences(of: "~", with: "")) }), v >= 0, v.isFinite {
                    rir = v; i += 1
                }
            case "left":
                if let v = value.flatMap(VelocitySet.Left.init), v != .failed { left = v; i += 1 }
            case "fail":
                left = .failed
            case "v1rm":
                if let v = value.flatMap(Double.init), v > 0, v.isFinite { v1rm = v; i += 1 }
            case "scale":
                // `scale ±1.2% height,plate,rack`: either part may be missing.
                if let v = value, v.hasPrefix("±"),
                   let p = Double(v.dropFirst().replacingOccurrences(of: "%", with: "")), p >= 0, p < 50 {
                    scale = p / 100; i += 1
                }
                if let v = tokens[safe: i + 1], v.contains(",") || ["height", "plate", "rack"].contains(v.lowercased()) {
                    let names = VelocitySet.rulerNames(v)
                    if !names.isEmpty { rulers = names; i += 1 }
                }
            default:
                break
            }
            i += 1
        }

        self.date = date
        self.lift = name.joined(separator: " ")
        self.setNumber = setNumber
        self.logged = logged
        self.mcv = mcv
        self.loss = loss ?? VelocityRecord.computedLoss(mcv)
        self.rirEstimate = rir
        self.left = left
        self.v1rm = v1rm
        self.scale = scale
        self.rulers = rulers
    }

    /// Loss as `VelocitySet` works it out: last rep against the fastest.
    static func computedLoss(_ mcv: [Double]) -> Double? {
        guard let best = mcv.max(), best > 0, let last = mcv.last else { return nil }
        return max(0, (best - last) / best)
    }

    /// Every measured set in the file, in file order. Headers, prose and
    /// malformed lines are skipped.
    static func parse(_ file: String) -> [VelocityRecord] {
        file.split(whereSeparator: \.isNewline).compactMap { VelocityRecord(line: String($0)) }
    }

    /// One lift's measured sets, oldest first: by day, then set number, then
    /// file order. The lift is matched the way the log matches it.
    static func records(for lift: String, in records: [VelocityRecord]) -> [VelocityRecord] {
        records.enumerated()
            .filter { Analytics.matches($0.element.lift, lift) }
            .sorted { a, b in
                if a.element.date != b.element.date { return a.element.date < b.element.date }
                let na = a.element.setNumber ?? 0, nb = b.element.setNumber ?? 0
                if na != nb { return na < nb }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// The newest set with a velocity 1RM, from sets oldest first.
    static func latestV1RM(_ sorted: [VelocityRecord]) -> VelocityRecord? {
        sorted.last { $0.v1rm != nil }
    }

    // MARK: - Same load

    /// The latest set against the most recent set of the same lift at the same
    /// load on an earlier day.
    struct Comparison: Equatable {
        var latest: VelocityRecord
        var earlier: VelocityRecord
        /// Best MCV, latest minus earlier, m/s, to the hundredth.
        var delta: Double
        /// The same as a share of the earlier, in percent.
        var percent: Double

        /// Within ±0.01 m/s: the same velocity, as far as a camera can tell.
        var isSame: Bool { abs(delta) <= 0.01 + 1e-9 }
        var isFaster: Bool { !isSame && delta > 0 }

        /// `at 110 kg: 0.03 m/s faster than 29 Sep`, the day as `day` spells it.
        func sentence(day: (Date) -> String) -> String {
            let when = day(earlier.date)
            if isSame { return "at \(latest.loadLabel): same velocity as \(when)" }
            return "at \(latest.loadLabel): \(VelocitySet.speed(abs(delta))) m/s \(delta > 0 ? "faster" : "slower") than \(when)"
        }
    }

    /// From one lift's sets, oldest first (`records(for:in:)`). Nil when the
    /// latest has no earlier day at its load.
    static func sameLoadComparison(_ sorted: [VelocityRecord]) -> Comparison? {
        guard let latest = sorted.last,
              let earlier = sorted.last(where: { $0.date < latest.date && $0.sameLoad(as: latest) }),
              earlier.best > 0
        else { return nil }
        let delta = ((latest.best - earlier.best) * 100).rounded() / 100
        return Comparison(latest: latest, earlier: earlier, delta: delta,
                          percent: (latest.best - earlier.best) / earlier.best * 100)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
