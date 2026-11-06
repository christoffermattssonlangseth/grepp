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
/// Fitness moves the line, so only sets from the last twelve weeks (counted from
/// today) count. A profile needs three sets over loads at least 10% apart whose
/// speeds fall near a line; with less, `fit` says what's missing. A 1RM and loads
/// for target speeds are only given when the line is clear (r² ≥ 0.7) and the 1RM
/// is no more than 30% beyond the heaviest load lifted: three sets close in load
/// can otherwise put it at five hundred kilos.
struct LoadVelocityProfile: Equatable {
    struct Point: Equatable {
        var date: Date
        var load: Double
        var mcv: Double
    }

    /// Sets older than this many days, counted back from today, are left out.
    static let windowDays = 84
    static let window: TimeInterval = Double(windowDays) * 86_400
    /// Below this the sets don't make a line at all; below `clearFit` no 1RM.
    static let minFit = 0.5
    static let clearFit = 0.7
    /// A 1RM further than this beyond the heaviest load is an extrapolation too far.
    static let maxReach = 1.3
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
    /// Clear enough to read a 1RM and target loads off.
    var isClear: Bool { rSquared >= Self.clearFit }
    func load(at speed: Double) -> Double { (speed - intercept) / slope }

    /// The load at which the line meets the threshold, kg; nil without one or
    /// when it lands somewhere a 1RM can't be (below the loads lifted).
    var oneRepMax: Double? {
        guard let threshold, isClear else { return nil }
        let l = load(at: threshold), top = loads.upperBound
        guard l.isFinite else { return nil }
        if l >= top { return l <= Self.maxReach * top ? l : nil }
        // The line puts the 1RM below a load already lifted (a heavy set near the
        // threshold): the 1RM is at least that load.
        return top
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
    /// Keyed by Grepp's own name for the lift (`ohp` is the overhead press, `dl`
    /// the deadlift); other lifts, a leg press or a split squat, get none.
    static func typicalThreshold(_ lift: String) -> Double? {
        switch MuscleMap.canonical(lift) {
        case "squat", "front-squat": return 0.30
        case "bench-press": return 0.17
        case "deadlift": return 0.15
        case "over-head-press": return 0.19
        default: return nil
        }
    }

    /// Whether `date` is within the window, by calendar days back from `now`.
    static func recent(_ date: Date, now: Date) -> Bool {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        return days <= windowDays
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
    static func fit(_ records: [VelocityRecord], lift: String, now: Date = Date()) -> Fit {
        let loaded = records.filter { ($0.load ?? 0) > 0 && $0.best > 0 }
        guard let newest = loaded.map(\.date).max() else { return .none }
        let recent = loaded.filter { Self.recent($0.date, now: now) }
        guard !recent.isEmpty else {
            return .needsMore("No measured sets in the last 12 weeks; the latest was on "
                + newest.formatted(.dateTime.day().month(.abbreviated).year()) + ".")
        }
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
        let r2 = ssTot > 0 ? max(0, 1 - ssRes / ssTot) : 0
        if r2 < minFit {
            return .needsMore("The sets so far don't fall on a line yet (r² \(String(format: "%.2f", r2)) over \(range)); "
                + "a few more sets at clearly different loads will settle it.")
        }
        let own = VelocityRecord.failureSpeeds(records).filter { Self.recent($0.date, now: now) }.map(\.speed)
        let threshold = own.isEmpty ? typicalThreshold(lift) : own.sorted()[own.count / 2]
        return .profile(LoadVelocityProfile(
            intercept: a, slope: b, points: points,
            rSquared: r2,
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
        guard isClear else { return [] }
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

    /// The latest day with a loaded set, judged against the profile fitted without
    /// that day (a set can't be judged against a line it pulled), using the day's
    /// first loaded set, the least tired: the set and how much faster (+) or slower
    /// (−) it moved than predicted, percent.
    static func readiness(_ records: [VelocityRecord], lift: String, now: Date = Date())
        -> (record: VelocityRecord, percent: Double)? {
        let loaded = records.filter { ($0.load ?? 0) > 0 && $0.best > 0 }
        guard let day = loaded.map(\.date).max(), Self.recent(day, now: now),
              let first = loaded.first(where: { $0.date == day }),
              case .profile(let p) = fit(records.filter { $0.date < day }, lift: lift, now: now),
              let d = p.readiness(first) else { return nil }
        return (first, d)
    }

    /// "on the profile" within ±3%, else "6% faster than the profile".
    static func readinessText(_ d: Double) -> String {
        abs(d) < 3 ? "on the profile" : "\(Int(abs(d).rounded()))% \(d > 0 ? "faster" : "slower") than the profile"
    }

    /// The coach's line.
    func coachLine(lift: String, readiness: (record: VelocityRecord, percent: Double)?) -> String {
        var parts = ["\(lift): v = \(String(format: "%.2f", intercept)) − \(String(format: "%.4f", -slope))·kg",
                     "\(points.count) sets, \(WorkSet.formatWeight(loads.lowerBound))–\(WorkSet.formatWeight(loads.upperBound)) kg",
                     "r² \(String(format: "%.2f", rSquared)), ±\(VelocitySet.speed(scatter)) m/s"]
        if let rm = oneRepMax, let t = threshold {
            parts.append("est. 1RM ≈ \(WorkSet.formatWeight((rm / 2.5).rounded() * 2.5)) kg at "
                         + "\(VelocitySet.speed(t)) m/s (\(thresholdIsOwn ? "own" : "typical") threshold)")
        }
        if let (r, d) = readiness, let load = r.load {
            parts.append("latest day's first set, \(WorkSet.formatWeight(load)) kg: \(Self.readinessText(d))")
        }
        let table = loadsForSpeeds.map { "\(VelocitySet.speed($0.speed)) m/s ≈ \(WorkSet.formatWeight($0.load)) kg" }
        if !table.isEmpty { parts.append("loads: " + table.joined(separator: ", ")) }
        return parts.joined(separator: "; ")
    }
}
