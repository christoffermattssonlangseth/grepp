import Foundation

/// A lift's load–velocity profile: how fast the bar moves at each load, from the
/// sets BarVelo measured, as velocity-based training uses it.
///
/// Each measured set with a load gives one point: the load and the mean
/// concentric velocity of its fastest rep, the rep least touched by fatigue. Over
/// a training block those points fall close to a straight line, velocity
/// dropping as load rises. Three things are read off it:
///
/// - **An estimated 1RM**, without testing one: the load at which the line
///   reaches the minimum velocity threshold, the speed of a last possible rep.
///   That is the lifter's own once velocity.md holds a set taken to failure (the
///   last rep's speed), otherwise a typical value for the lift.
/// - **Readiness**: a set faster than the line predicts at its load is a good
///   day; slower, a tired one.
/// - **Loads for a target speed**: the load that should move at, say, 0.50 m/s.
///
/// Fitness moves the line, so only the last twelve weeks count. A profile needs
/// three sets over loads at least 10% apart; with less, `fit` says what's missing.
struct LoadVelocityProfile: Equatable {
    struct Point: Equatable {
        var date: Date
        var load: Double
        var mcv: Double
    }

    /// Sets older than this, counted back from the newest, are left out.
    static let window: TimeInterval = 84 * 86_400
    static let minSets = 3
    /// The loads must span at least this share of the heaviest.
    static let minSpread = 0.10

    /// v = intercept + slope · load (m/s, kg).
    var intercept: Double
    var slope: Double
    var points: [Point]
    /// Share of the variation in speed the line explains, 0…1.
    var rSquared: Double
    /// Typical distance of a set from the line, m/s.
    var scatter: Double
    /// Minimum velocity threshold, m/s; nil when neither the lifter's nor a
    /// typical one is known for the lift.
    var threshold: Double?
    /// The threshold is the lifter's own (from sets taken to failure).
    var thresholdIsOwn: Bool

    var loads: ClosedRange<Double> { points.map(\.load).min()!...points.map(\.load).max()! }

    func speed(at load: Double) -> Double { intercept + slope * load }
    func load(at speed: Double) -> Double { (speed - intercept) / slope }

    /// The load at which the line meets the threshold, kg; nil without one or
    /// when it lands somewhere a 1RM can't be (below the loads lifted).
    var oneRepMax: Double? {
        guard let threshold else { return nil }
        let l = load(at: threshold)
        return l.isFinite && l >= loads.upperBound ? l : nil
    }

    /// How much faster (+) or slower (−) a set moved than the line predicts at
    /// its load, percent of the prediction.
    func readiness(_ r: VelocityRecord) -> Double? {
        guard let load = r.load, load > 0, r.best > 0 else { return nil }
        let p = speed(at: load)
        return p > 0 ? (r.best - p) / p * 100 : nil
    }

    /// Typical speeds of a last possible rep, m/s, used until the lifter has their
    /// own. Group values vary between studies and people; they only seed the 1RM.
    static func typicalThreshold(_ lift: String) -> Double? {
        let l = lift.lowercased()
        if l.contains("squat") { return 0.30 }
        if l.contains("bench") { return 0.17 }
        if l.contains("deadlift") { return 0.15 }
        if l.contains("press") { return 0.19 }
        return nil
    }

    /// What the records make of the lift.
    enum Fit: Equatable {
        case profile(LoadVelocityProfile)
        /// Measured sets exist but don't make a profile yet; the sentence says why.
        case needsMore(String)
        /// No measured sets with a load: nothing to show.
        case none
    }

    /// One lift's profile from its measured sets (`VelocityRecord.records(for:in:)`).
    static func fit(_ records: [VelocityRecord], lift: String) -> Fit {
        let loaded = records.filter { ($0.load ?? 0) > 0 && $0.best > 0 }
        guard let newest = loaded.map(\.date).max() else { return .none }
        let recent = loaded.filter { newest.timeIntervalSince($0.date) <= window }
        let points = recent.map { Point(date: $0.date, load: $0.load!, mcv: $0.best) }
        let loads = points.map(\.load)
        let lo = loads.min()!, hi = loads.max()!
        let range = lo == hi ? "\(WorkSet.formatWeight(lo)) kg" : "\(WorkSet.formatWeight(lo))–\(WorkSet.formatWeight(hi)) kg"

        if points.count < minSets {
            let more = minSets - points.count
            return .needsMore("The profile needs \(more) more measured \(more == 1 ? "set" : "sets")"
                + (hi - lo < minSpread * hi ? ", at loads at least 10% apart" : "")
                + ". So far: \(points.count) at \(range).")
        }
        if hi - lo < minSpread * hi {
            return .needsMore("The profile needs a set at a load about 10% lighter or heavier: "
                + "so far \(points.count) sets, all at \(range).")
        }
        guard let (a, b) = line(points), b < 0 else {
            return .needsMore("Heavier sets haven't been slower yet across \(range); "
                + "the profile needs a few more sets to settle.")
        }

        let mean = points.map(\.mcv).reduce(0, +) / Double(points.count)
        let ssTot = points.map { ($0.mcv - mean) * ($0.mcv - mean) }.reduce(0, +)
        let ssRes = points.map { p in (p.mcv - (a + b * p.load)) * (p.mcv - (a + b * p.load)) }.reduce(0, +)
        let own = VelocityRecord.failureSpeeds(records).filter { newest.timeIntervalSince($0.date) <= window }.map(\.speed)
        let threshold = own.isEmpty ? typicalThreshold(lift) : own.sorted()[own.count / 2]
        return .profile(LoadVelocityProfile(
            intercept: a, slope: b, points: points,
            rSquared: ssTot > 0 ? max(0, 1 - ssRes / ssTot) : 0,
            scatter: points.count > 2 ? (ssRes / Double(points.count - 2)).squareRoot() : 0,
            threshold: threshold, thresholdIsOwn: !own.isEmpty))
    }

    /// Ordinary least squares of speed on load; nil when every load is the same.
    private static func line(_ p: [Point]) -> (Double, Double)? {
        let n = Double(p.count)
        let mx = p.map(\.load).reduce(0, +) / n, my = p.map(\.mcv).reduce(0, +) / n
        let sxx = p.map { ($0.load - mx) * ($0.load - mx) }.reduce(0, +)
        guard sxx > 1e-9 else { return nil }
        let sxy = p.map { ($0.load - mx) * ($0.mcv - my) }.reduce(0, +)
        return (my - sxy / sxx * mx, sxy / sxx)
    }

    // MARK: - Reading it out

    /// Loads, to the nearest 2.5 kg, for up to three round speeds (every 0.05 m/s)
    /// within the speeds the profile saw: `[(0.50, 92.5), (0.45, 100), (0.40, 107.5)]`.
    var loadsForSpeeds: [(speed: Double, load: Double)] {
        let speeds = points.map(\.mcv)
        let first = Int((speeds.min()! * 20).rounded(.up)), last = Int((speeds.max()! * 20).rounded(.down))
        var steps = first <= last ? Array(first...last) : [Int((speeds.reduce(0, +) / Double(speeds.count) * 20).rounded())]
        if steps.count > 3 { steps = [steps.first!, steps[steps.count / 2], steps.last!] }
        return steps.reversed().compactMap { s in
            let v = Double(s) / 20
            let l = (load(at: v) / 2.5).rounded() * 2.5
            return l > 0 ? (v, l) : nil
        }
    }

    /// `Squat: 0.0093 m/s slower per kg (6 sets, 85–120 kg); estimated 1RM ≈
    /// 128 kg at 0.30 m/s, a typical threshold.`
    func summary(lift: String) -> String {
        let r = loads
        var s = "\(lift): \(String(format: "%.4f", -slope)) m/s slower per kg "
            + "(\(points.count) sets, \(WorkSet.formatWeight(r.lowerBound))–\(WorkSet.formatWeight(r.upperBound)) kg)"
        if let rm = oneRepMax, let t = threshold {
            s += "; estimated 1RM ≈ \(WorkSet.formatWeight((rm / 2.5).rounded() * 2.5)) kg at "
                + "\(VelocitySet.speed(t)) m/s, \(thresholdIsOwn ? "your own failure speed" : "a typical threshold")"
        }
        return s + "."
    }

    /// The coach's line.
    func coachLine(lift: String, latest: VelocityRecord?) -> String {
        var parts = ["\(lift): v = \(String(format: "%.2f", intercept)) − \(String(format: "%.4f", -slope))·kg",
                     "\(points.count) sets, \(WorkSet.formatWeight(loads.lowerBound))–\(WorkSet.formatWeight(loads.upperBound)) kg",
                     "r² \(String(format: "%.2f", rSquared)), ±\(VelocitySet.speed(scatter)) m/s"]
        if let rm = oneRepMax, let t = threshold {
            parts.append("est. 1RM ≈ \(WorkSet.formatWeight((rm / 2.5).rounded() * 2.5)) kg at "
                         + "\(VelocitySet.speed(t)) m/s (\(thresholdIsOwn ? "own" : "typical") threshold)")
        }
        if let latest, let d = readiness(latest), let load = latest.load {
            parts.append("latest set at \(WorkSet.formatWeight(load)) kg \(String(format: "%+.0f", d))% vs profile")
        }
        let table = loadsForSpeeds.map { "\(VelocitySet.speed($0.speed)) m/s ≈ \(WorkSet.formatWeight($0.load)) kg" }
        if !table.isEmpty { parts.append("loads: " + table.joined(separator: ", ")) }
        return parts.joined(separator: "; ")
    }
}
