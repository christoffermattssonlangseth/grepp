import Foundation

/// What to put on each side of the bar. Pure arithmetic, so it lives in Core
/// with the other logic and is tested on the command line.
enum PlateMath {

    /// A standard kilo set, largest first. Greedy loading is exact for this set
    /// because every plate is a multiple of the smallest.
    static let standardPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    struct Load: Equatable {
        /// Plates per side, largest first. Empty means the bar alone.
        var perSide: [Double]
        /// The target can't be made from these plates; this is the nearest below —
        /// 86 kg, say, when the smallest plate is 1.25.
        var isApproximate: Bool
        /// What actually ends up on the bar.
        var total: Double
    }

    /// Nil when the target is lighter than the bar — nothing sensible to say.
    static func load(_ target: Double, bar: Double = 20, plates: [Double] = standardPlates) -> Load? {
        guard target >= bar else { return nil }
        var remaining = (target - bar) / 2
        var perSide: [Double] = []
        for plate in plates.sorted(by: >) {
            // A hair of tolerance: 33.75 - 25 - 5 - 2.5 is not exactly 1.25 in binary.
            while remaining + 0.0001 >= plate {
                perSide.append(plate)
                remaining -= plate
            }
        }
        return Load(perSide: perSide,
                    isApproximate: remaining > 0.0001,
                    total: bar + 2 * perSide.reduce(0, +))
    }
}
