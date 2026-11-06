import Foundation

/// Bar speed against reps in reserve, from the lifter's own answers.
///
/// `mcv` lists only completed reps. `fail` means the last listed rep had
/// nothing left; `left N` means N more were possible after it. So in a
/// labelled set of n reps, rep k (from 1) had `left + (n − k)` in reserve, and
/// every labelled set gives a point per rep: how fast the bar moved with that
/// many reps still in the tank. A line through those points reads a set's
/// last-rep speed as reps left, filmed the same way.
extension VelocityRecord {

    /// Reps in reserve at the end of the set, in the lifter's own words: 0 for
    /// `fail`, N for `left N`; nil without an answer.
    var ownReserve: Int? {
        switch left {
        case .failed?: return 0
        case .reps(let n)?: return n
        case nil: return nil
        }
    }

    /// One labelled rep: its speed and the reps it had in reserve.
    struct ReservePoint: Equatable {
        var mcv: Double
        var reserve: Int
    }

    /// Every rep of a labelled set with its reps in reserve; empty without an
    /// answer.
    var reservePoints: [ReservePoint] {
        guard let left = ownReserve else { return [] }
        let n = mcv.count
        return mcv.enumerated().map { k, v in ReservePoint(mcv: v, reserve: left + (n - 1 - k)) }
    }
}

/// Least squares, reps in reserve = a + b · MCV, over a lift's labelled reps
/// with five or fewer in reserve: further out the line bends and the answers
/// get vaguer. Valid only with four such reps and a slope that says faster is
/// further from failure.
struct ReserveModel: Equatable {
    /// Points further from failure than this are left out of the fit.
    static let maxReserve = 5
    static let minPoints = 4

    var a: Double
    var b: Double
    /// Labelled sets that gave the fit at least one rep.
    var labelledSets: Int
    /// Reps the line was fitted to.
    var points: Int
    /// Leave-one-out mean absolute error, reps: refit without each rep in
    /// turn and see how far off it is read.
    var looError: Double
    /// The speeds the fit saw, slowest to fastest, m/s.
    var observed: ClosedRange<Double>

    /// The speed at which nothing is left, m/s.
    var failureSpeed: Double { -a / b }
    /// How much faster the bar moves per rep in reserve, m/s.
    var speedPerRep: Double { 1 / b }

    /// Reps in reserve at a last-rep speed; never below 0.
    func reserve(at speed: Double) -> Double { max(0, a + b * speed) }

    /// Fit from one lift's sets (`VelocityRecord.records(for:in:)`). Nil
    /// with too few labelled reps or a flat or backwards line.
    static func fit(_ records: [VelocityRecord]) -> ReserveModel? {
        var points: [VelocityRecord.ReservePoint] = []
        var sets = 0
        for r in records {
            let p = r.reservePoints.filter { $0.reserve <= maxReserve }
            if !p.isEmpty { sets += 1; points += p }
        }
        guard points.count >= minPoints,
              let (a, b) = line(points), b > 0, a.isFinite, b.isFinite else { return nil }

        var errors: [Double] = []
        for i in points.indices {
            var rest = points
            let out = rest.remove(at: i)
            if let (la, lb) = line(rest) { errors.append(abs(la + lb * out.mcv - Double(out.reserve))) }
        }
        let speeds = points.map(\.mcv)
        return ReserveModel(a: a, b: b, labelledSets: sets, points: points.count,
                            looError: errors.isEmpty ? .nan : errors.reduce(0, +) / Double(errors.count),
                            observed: speeds.min()!...speeds.max()!)
    }

    /// Ordinary least squares of reserve on speed; nil when every speed is
    /// the same.
    private static func line(_ p: [VelocityRecord.ReservePoint]) -> (Double, Double)? {
        guard p.count >= 2 else { return nil }
        let n = Double(p.count)
        let mx = p.map(\.mcv).reduce(0, +) / n
        let my = p.map { Double($0.reserve) }.reduce(0, +) / n
        let sxx = p.map { ($0.mcv - mx) * ($0.mcv - mx) }.reduce(0, +)
        guard sxx > 1e-12 else { return nil }
        let sxy = p.map { ($0.mcv - mx) * (Double($0.reserve) - my) }.reduce(0, +)
        let b = sxy / sxx
        return (my - b * mx, b)
    }

    // MARK: - Reading it out

    /// Two or three round speeds, every 0.05 m/s, inside what the fit saw,
    /// with the reps left at each, rounded: `[(0.30, 1), (0.35, 2), (0.40, 3)]`.
    var lookup: [(speed: Double, reserve: Int)] {
        let first = Int((observed.lowerBound * 20).rounded(.up))
        let last = Int((observed.upperBound * 20).rounded(.down))
        guard first <= last else {
            let mid = ((observed.lowerBound + observed.upperBound) / 2 * 100).rounded() / 100
            return [(mid, Int(reserve(at: mid).rounded()))]
        }
        var steps = Array(first...last)
        if steps.count > 3 {
            // Slowest, middle, fastest.
            steps = [steps.first!, steps[steps.count / 2], steps.last!]
        }
        return steps.map { s in
            let v = Double(s) / 20
            return (v, Int(reserve(at: v).rounded()))
        }
    }

    /// `±0.6 reps`, or nothing when it couldn't be worked out.
    private var errorLabel: String? {
        looError.isFinite ? "±\(VelocitySet.tenth(looError)) reps" : nil
    }

    /// The card's sentence: `Overhead press: failure ≈ 0.27 m/s, about 0.04
    /// m/s per rep in reserve (1 labelled set, ±0.6 reps). Filmed the same
    /// way, 0.40 m/s ≈ 3 left.`
    func summary(lift: String) -> String {
        var paren = ["\(labelledSets) labelled \(labelledSets == 1 ? "set" : "sets")"]
        if let errorLabel { paren.append(errorLabel) }
        var s = "\(lift): failure ≈ \(VelocitySet.speed(failureSpeed)) m/s, about "
            + "\(VelocitySet.speed(speedPerRep)) m/s per rep in reserve (\(paren.joined(separator: ", ")))."
        let table = lookup
        if !table.isEmpty {
            let anchor = table[table.count / 2]
            s += " Filmed the same way, \(VelocitySet.speed(anchor.speed)) m/s ≈ \(anchor.reserve) left."
        }
        return s
    }

    /// The coach's line: `over-head-press: failure ≈ 0.27 m/s, 0.039 m/s per
    /// rep in reserve, 1 labelled set, ±0.6 reps`.
    func coachLine(lift: String) -> String {
        var parts = ["\(lift): failure ≈ \(VelocitySet.speed(failureSpeed)) m/s",
                     "\(String(format: "%.3f", speedPerRep)) m/s per rep in reserve",
                     "\(labelledSets) labelled \(labelledSets == 1 ? "set" : "sets")"]
        if let errorLabel { parts.append(errorLabel) }
        return parts.joined(separator: ", ")
    }
}

extension VelocityRecord {

    /// How close a measured set ended to failure: reps in reserve after its
    /// last rep.
    struct Proximity: Equatable {
        var record: VelocityRecord
        var reserve: Double
        /// The lifter said so (`fail`, `left N`); otherwise it was read off
        /// the last rep's speed.
        var isOwn: Bool
        var date: Date { record.date }
    }

    /// One lift's sets, oldest first, each with reps in reserve at its end:
    /// the lifter's own answer when there is one, else the model's reading of
    /// the last rep. Sets with neither are left out.
    static func proximity(_ records: [VelocityRecord], model: ReserveModel?) -> [Proximity] {
        records.compactMap { r in
            if let own = r.ownReserve { return Proximity(record: r, reserve: Double(own), isOwn: true) }
            guard let model, !r.mcv.isEmpty else { return nil }
            return Proximity(record: r, reserve: model.reserve(at: r.lastRep), isOwn: false)
        }
    }

    /// The last rep of each set that ended at failure (`fail`, `left 0`),
    /// oldest first: how fast this lifter's bar moves when nothing is left.
    static func failureSpeeds(_ records: [VelocityRecord]) -> [(date: Date, speed: Double)] {
        records.compactMap { r in
            r.ownReserve == 0 && !r.mcv.isEmpty ? (r.date, r.lastRep) : nil
        }
    }

    /// Days with at least one labelled set.
    static func labelledDays(_ records: [VelocityRecord]) -> Int {
        Set(records.filter { $0.ownReserve != nil }.map(\.date)).count
    }

    /// Each lift in the file once, spelled as it first appears, with its
    /// sets oldest first; lifts the log treats as one are one.
    static func byLift(_ records: [VelocityRecord]) -> [(lift: String, records: [VelocityRecord])] {
        var names: [String] = []
        for r in records where !names.contains(where: { Analytics.matches($0, r.lift) }) {
            names.append(r.lift)
        }
        return names.map { ($0, Self.records(for: $0, in: records)) }
    }
}
