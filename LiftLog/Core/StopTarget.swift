import Foundation

/// Where the owner stops a set by velocity loss, as BarVelo calls it: 40% on
/// presses and the bench, which lose more speed before they fail, 35% on
/// everything else. These are BarVelo's defaults (`StopTargets` there), aimed
/// at about one or two reps left; a target changed in BarVelo isn't sent here.
enum StopTarget {
    static let presses = 0.40
    static let others = 0.35

    /// The loss, 0…1, BarVelo stops this lift at by default.
    static func loss(for lift: String) -> Double {
        let k = VelocitySet.kebab(MuscleMap.canonical(lift))
        let upper = ["press", "bench", "ohp", "dip", "push", "jerk"]
        return upper.contains(where: { k.contains($0) }) && !k.contains("leg-press") ? presses : others
    }

    /// `40%`.
    static func label(for lift: String) -> String { "\(Int((loss(for: lift) * 100).rounded()))%" }
}
