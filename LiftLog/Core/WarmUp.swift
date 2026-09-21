import Foundation

/// The sets before the first working set: the bar for ten, then half, seven
/// tenths and eighty-five hundredths of the top set for five, three and one.
/// Arithmetic on today's top set, rounded down to what the rack can load,
/// so the ramp is read off the screen instead of worked out at the rack.
/// Warm-ups are not logged: the file holds working sets.
enum WarmUp {
    struct Rung: Equatable {
        let weight: Double
        let reps: Int
        /// Plates a side, largest first; empty for the bar alone.
        let perSide: [Double]
    }

    /// Share of the top set and reps at it, lightest first.
    static let steps: [(share: Double, reps: Int)] = [(0.5, 5), (0.7, 3), (0.85, 1)]

    /// The ramp up to `top`, or nil when there is nothing to ramp to: a top
    /// set at or under the bar. Each rung rounds down to the nearest 2.5
    /// and then to what the rack can make; rungs that fall on the bar, on
    /// an earlier rung, or on the top set itself are left out.
    static func ramp(to top: Double, bar: Double = 20, inventory: PlateInventory = .standard) -> [Rung]? {
        guard top > bar else { return nil }
        var rungs = [Rung(weight: bar, reps: 10, perSide: [])]
        for step in steps {
            let raw = (top * step.share / 2.5).rounded(.down) * 2.5
            guard raw > bar, raw < top else { continue }
            let load = PlateMath.load(raw, bar: bar, inventory: inventory)
            let weight = load?.total ?? raw
            guard weight > rungs[rungs.count - 1].weight, weight < top else { continue }
            rungs.append(Rung(weight: weight, reps: step.reps, perSide: load?.perSide ?? []))
        }
        return rungs
    }

    /// "bar ×10 · 50 (15) ×5 · 70 (25) ×3 · 85 (25+7.5) ×1" — the load, its
    /// plates a side in brackets, and the reps.
    static func line(_ rungs: [Rung], bar: Double) -> String {
        rungs.map { rung in
            if rung.weight == bar { return "bar ×\(rung.reps)" }
            let plates = rung.perSide.map { PlateMath.label($0) }.joined(separator: "+")
            let load = PlateMath.label(rung.weight)
            return plates.isEmpty ? "\(load) ×\(rung.reps)" : "\(load) (\(plates)) ×\(rung.reps)"
        }.joined(separator: " · ")
    }
}
