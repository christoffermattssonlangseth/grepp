import Foundation

/// One day's measured sets of a lift, read the way the owner asks after a
/// session: how fast each set started and ended, how far past the stop
/// target it went, how many reps were left, and whether the first rep slowed
/// from set to set (fatigue building).
struct VelocitySession: Equatable {
    struct Row: Equatable {
        var record: VelocityRecord
        /// Loss at the end of the set, 0…1.
        var loss: Double?
        /// Went past the lift's stop target.
        var pastTarget: Bool
        /// Reps left at the end: the lifter's own, else the gated model's.
        var reserve: Double?
        var reserveIsOwn: Bool
        /// Fastest rep against set 1's fastest, percent; nil for the first.
        var firstRepChange: Double?

        /// `set 3 · 73.5×12 · 0.40 → 0.19 · −53% · 0 left`.
        var text: String {
            var parts: [String] = []
            if let n = record.setNumber { parts.append("set \(n)") }
            parts.append(record.logged.token.replacingOccurrences(of: "x", with: "×"))
            parts.append(record.mcv.count == 1 ? VelocitySet.speed(record.best)
                         : "\(VelocitySet.speed(record.best)) → \(VelocitySet.speed(record.lastRep))")
            if let loss, record.mcv.count > 1 { parts.append("−\(Int((loss * 100).rounded()))%") }
            if record.left == .failed {
                parts.append("fail")
            } else if let reserve {
                parts.append(reserveIsOwn ? "\(Int(reserve)) left"
                             : "≈\(VelocitySet.tenth((reserve * 2).rounded() / 2)) left (est.)")
            }
            return parts.joined(separator: " · ")
        }
    }

    var date: Date
    var lift: String
    /// The lift's stop target, 0…1.
    var target: Double
    var rows: [Row]

    /// Sets that went past the stop target.
    var pastTarget: Int { rows.filter(\.pastTarget).count }

    /// `stop target 40%: 2 of 3 sets went past it`, or `… none went past it`.
    var targetLine: String {
        let t = "stop target \(Int((target * 100).rounded()))%"
        let measured = rows.filter { $0.record.mcv.count > 1 }.count
        guard measured > 0 else { return t }
        if pastTarget == 0 { return "\(t): no set went past it" }
        return "\(t): \(pastTarget) of \(measured) \(measured == 1 ? "set" : "sets") went past it"
    }

    /// `first rep, last set against set 1: −4%`; nil with one set.
    var fatigueLine: String? {
        guard rows.count > 1, let change = rows.last?.firstRepChange else { return nil }
        let pct = Int(change.rounded())
        return "fastest rep, last set against the first: \(pct > 0 ? "+" : pct < 0 ? "−" : "±")\(abs(pct))%"
    }

    /// The newest day's sets of one lift (`VelocityRecord.records(for:in:)`,
    /// oldest first), with reps left from `model` when the lifter gave none.
    static func latest(_ sorted: [VelocityRecord], lift: String, model: ReserveModel?) -> VelocitySession? {
        guard let day = sorted.last?.date else { return nil }
        let sets = sorted.filter { $0.date == day }
        let target = StopTarget.loss(for: lift)
        let firstBest = sets.first?.best ?? 0
        let rows = sets.enumerated().map { i, r -> Row in
            let own = r.ownReserve.map(Double.init)
            let est = own == nil && !r.mcv.isEmpty ? model?.reserve(at: r.lastRep) : nil
            return Row(record: r, loss: r.loss,
                       pastTarget: r.mcv.count > 1 && (r.loss ?? 0) > target + 1e-9,
                       reserve: own ?? est, reserveIsOwn: own != nil,
                       firstRepChange: i > 0 && firstBest > 0 ? (r.best - firstBest) / firstBest * 100 : nil)
        }
        return VelocitySession(date: day, lift: lift, target: target, rows: rows)
    }
}
