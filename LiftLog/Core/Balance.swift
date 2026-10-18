import Foundation

/// Two sides of the body against each other, in sets a week: push against
/// pull, quads against hamstrings. The pairs that, left uneven for long,
/// are how shoulders and knees end up sore. Read over four weeks, since one
/// week's split is a scheduling accident.
enum Balance {
    struct Side: Equatable {
        let name: String
        let sets: Double
    }

    struct Pair: Equatable, Identifiable {
        var id: String { "\(a.name)-\(b.name)" }
        let a: Side
        let b: Side

        /// Under this share of the larger side, the smaller one is short.
        static let evenShare = 0.7
        /// Fewer sets than this between them and there is nothing to read.
        static let minimum = 4.0

        /// The side that is short, if one is.
        var short: Side? {
            guard a.sets + b.sets >= Pair.minimum else { return nil }
            let (small, large) = a.sets <= b.sets ? (a, b) : (b, a)
            return small.sets < large.sets * Pair.evenShare ? small : nil
        }

        /// "even" / "pull is short" / "too few sets to read".
        var verdict: String {
            if a.sets + b.sets < Pair.minimum { return "too few sets to read" }
            return short.map { "\($0.name) is short" } ?? "even"
        }
    }

    static let push: [MuscleGroup] = [.chest, .frontDelts, .sideDelts, .triceps]
    static let pull: [MuscleGroup] = [.back, .rearDelts, .biceps]

    /// The pairs, as sets a week averaged over `weeks`: weeks counted by
    /// `weeklySets`, so a set is one set of pushing however many push
    /// muscles it trains.
    static func pairs(over weeks: [MuscleMap.Credits]) -> [Pair] {
        guard !weeks.isEmpty else { return [] }
        func perWeek(_ groups: [MuscleGroup]) -> Double {
            let total = weeks.reduce(0.0) { sum, week in sum + groups.reduce(0.0) { $0 + (week[$1] ?? 0) } }
            return total / Double(weeks.count)
        }
        return [
            Pair(a: Side(name: "push", sets: perWeek(push)), b: Side(name: "pull", sets: perWeek(pull))),
            Pair(a: Side(name: "quads", sets: perWeek([.quads])), b: Side(name: "hamstrings", sets: perWeek([.hamstrings]))),
        ]
    }

    /// A lift's shares as the pairs count them: on each side, only its
    /// largest share. One overhead press is a full set for the front and the
    /// side delts and half for triceps — two and a half push sets by muscle,
    /// but one set of pushing. Muscles off the pairs are left as they are.
    static func counted(_ credits: MuscleMap.Credits) -> MuscleMap.Credits {
        var out = credits
        for side in [push, pull] {
            let present = side.filter { (credits[$0] ?? 0) > 0 }
            guard let top = present.max(by: { credits[$0]! < credits[$1]! }) else { continue }
            for group in present where group != top { out.removeValue(forKey: group) }
        }
        return out
    }

    /// Sets a week for the pairs, the last `weeks` weeks oldest first, on the
    /// same Monday weeks as the muscles' own counts, each set at most once a
    /// side.
    static func weeklySets(weeks: Int, endingOn today: Date = Date(), calendar: Calendar = .current,
                           in sessions: [Session], map: MuscleMap) -> [MuscleMap.Credits] {
        let grid = Analytics.weekGrid(weeks: weeks, endingOn: today, calendar: calendar, in: sessions)
        let byDay = Dictionary(grouping: sessions, by: \.dateString)
        return grid.map { week in
            var total: MuscleMap.Credits = [:]
            for key in week.days.compactMap({ $0?.key }) {
                for session in byDay[key] ?? [] {
                    for entry in session.exercises {
                        guard let credits = map.credits(for: entry.name) else { continue }
                        for (group, share) in counted(credits) {
                            total[group, default: 0] += share * Double(entry.sets.count)
                        }
                    }
                }
            }
            return total
        }
    }
}
