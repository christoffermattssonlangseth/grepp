import Foundation

/// What to put on each side of the bar. Pure arithmetic, so it lives in Core
/// with the other logic and is tested on the command line.
enum PlateMath {

    /// Every plate size the rack UI offers, largest first.
    static let sizes: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25, 0.5, 0.25]

    /// The smallest step any plate can be — everything is worked in these units
    /// so the search is over integers and there is no floating-point drift.
    static let unit = 0.25

    struct Load: Equatable {
        /// Plates per side, largest first. Empty means the bar alone.
        var perSide: [Double]
        /// The target can't be made from what's on the rack; this is the heaviest
        /// load that can, below it.
        var isApproximate: Bool
        /// What actually ends up on the bar.
        var total: Double
    }

    /// "1.25", "0.25", "2.5", "25" — the log's formatter rounds to one decimal,
    /// which would print a 1.25 as 1.2.
    static func label(_ kg: Double) -> String {
        var s = String(format: "%.2f", kg)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// Nil when the target is lighter than the bar — nothing sensible to say.
    ///
    /// A bounded knapsack over quarter-kilo units rather than greedy: greedy is
    /// exact only with unlimited plates. With one 15 and two 10s a side and 20 to
    /// load, greedy takes the 15, can't finish, and reports 15 — when 10 + 10 was
    /// right there. The search finds the exact load when one exists, otherwise the
    /// heaviest below; ties go to the fewest plates, then the heaviest ones, which
    /// is how a lifter loads a bar.
    static func load(_ target: Double, bar: Double = 20, inventory: PlateInventory = .standard) -> Load? {
        guard target >= bar else { return nil }
        let want = Int(((target - bar) / 2 / unit).rounded())

        // Per-side stock: a pair per side, so an odd plate out can't be used.
        let stock: [(units: Int, count: Int)] = inventory.counts
            .compactMap { size, total in
                let perSide = total / 2
                let units = Int((size / unit).rounded())
                return perSide > 0 && units > 0 ? (units, perSide) : nil
            }
            .sorted { $0.units > $1.units }

        // best[s]: the preferred way to load exactly s units, or nil if impossible.
        var best = [[Int]?](repeating: nil, count: want + 1)
        best[0] = []
        for (units, count) in stock {
            for s in stride(from: want, through: units, by: -1) {
                for k in 1...count where s >= k * units {
                    guard let prior = best[s - k * units] else { continue }
                    let candidate = (prior + Array(repeating: units, count: k)).sorted(by: >)
                    if let current = best[s], !prefers(candidate, over: current) { continue }
                    best[s] = candidate
                }
            }
        }

        let reached = (0...want).reversed().first { best[$0] != nil } ?? 0
        let perSide = (best[reached] ?? []).map { Double($0) * unit }
        return Load(perSide: perSide,
                    isApproximate: reached != want,
                    total: bar + 2 * Double(reached) * unit)
    }

    /// Fewer plates wins; on a tie, the heavier plates first — [25, 25, 25, 5]
    /// beats [20, 20, 20, 20] for the same 80 a side.
    private static func prefers(_ a: [Int], over b: [Int]) -> Bool {
        if a.count != b.count { return a.count < b.count }
        for (x, y) in zip(a, b) where x != y { return x > y }
        return false
    }
}

/// The plates you own, both sides together: four 25s means two a side.
///
/// Stored as a string so it fits in `AppStorage` — "25:4,15:2,…".
struct PlateInventory: Equatable, RawRepresentable {
    var counts: [Double: Int]

    init(counts: [Double: Int]) { self.counts = counts }

    init?(rawValue: String) {
        var counts: [Double: Int] = [:]
        for pair in rawValue.split(separator: ",") {
            let kv = pair.split(separator: ":")
            guard kv.count == 2, let size = Double(kv[0]), let n = Int(kv[1]) else { continue }
            counts[size] = n
        }
        self.counts = counts
    }

    var rawValue: String {
        counts.keys.sorted(by: >)
            .map { "\(PlateMath.label($0)):\(counts[$0] ?? 0)" }
            .joined(separator: ",")
    }

    /// A well-stocked commercial rack. What you get until you tell it otherwise.
    static let standard = PlateInventory(counts: [25: 8, 20: 8, 15: 4, 10: 4, 5: 4, 2.5: 4, 1.25: 4, 0.5: 0, 0.25: 0])
}
