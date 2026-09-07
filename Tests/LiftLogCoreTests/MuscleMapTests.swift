import XCTest
@testable import LiftLogCore

final class MuscleMapTests: XCTestCase {

    private func date(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }
    private func sets(_ n: Int) -> [WorkSet] { Array(repeating: WorkSet(weight: 80, added: nil, reps: 5), count: n) }
    private func entry(_ name: String, _ n: Int) -> ExerciseEntry { ExerciseEntry(name: name, sets: sets(n)) }

    func testCompoundsCountFullyForThePrimeMoverAndHalfForTheRest() {
        let map = MuscleMap()
        XCTAssertEqual(map.credits(for: "squat"), [.quads: 1, .glutes: 0.5])
        XCTAssertEqual(map.credits(for: "chin-ups"), [.back: 1, .biceps: 0.5])
        XCTAssertEqual(map.credits(for: "bench-press"), [.chest: 1, .triceps: 0.5, .frontDelts: 0.5])
        XCTAssertEqual(map.credits(for: "lateral-raise"), [.sideDelts: 1])
        XCTAssertEqual(map.credits(for: "seal-row"), [.back: 1, .biceps: 0.5, .rearDelts: 0.5])
        XCTAssertNil(map.credits(for: "sled-push"), "unknown lifts count nowhere")
    }

    func testAliasesAndSpellingsResolve() {
        let map = MuscleMap()
        XCTAssertEqual(map.credits(for: "Bench"), map.credits(for: "bench-press"))
        XCTAssertEqual(map.credits(for: "OHP"), map.credits(for: "over-head-press"))
        XCTAssertEqual(map.credits(for: "pull ups"), map.credits(for: "pull-ups"))
        XCTAssertEqual(map.credits(for: "romanian_deadlift"), map.credits(for: "rdl"))
    }

    func testOverridesWinAndRoundTrip() {
        var map = MuscleMap()
        map.set([.quads, .core], for: "Sled Push")
        map.set([.chest], for: "seal-row")   // says otherwise, so it's chest
        XCTAssertEqual(map.credits(for: "sled-push"), [.quads: 1, .core: 0.5])
        XCTAssertEqual(map.credits(for: "seal-row"), [.chest: 1])
        XCTAssertTrue(map.isOverridden("seal-row"))
        XCTAssertFalse(map.isOverridden("squat"))

        let raw = map.rawValue
        XCTAssertEqual(raw, "seal-row=chest;sled-push=quads+core")
        XCTAssertEqual(MuscleMap(rawValue: raw), map)

        map.set([], for: "seal-row")
        XCTAssertEqual(map.credits(for: "seal-row"), [.back: 1, .biceps: 0.5, .rearDelts: 0.5], "cleared — back to the table")
        XCTAssertEqual(MuscleMap(rawValue: "junk;x=;y=nothing")?.overrides, [:])
    }

    func testSetsPerMuscleForASession() {
        let session = Session(date: date("2026-09-01"), exercises: [
            entry("squat", 3), entry("bench-press", 3), entry("chin-ups", 4), entry("sled-push", 5),
        ])
        let counted = MuscleMap().sets(in: [session])
        XCTAssertEqual(counted[.quads], 3)
        XCTAssertEqual(counted[.glutes], 1.5)
        XCTAssertEqual(counted[.chest], 3)
        XCTAssertEqual(counted[.triceps], 1.5)
        XCTAssertEqual(counted[.frontDelts], 1.5)
        XCTAssertNil(counted[.sideDelts], "a bench day is not side-delt work")
        XCTAssertEqual(counted[.back], 4)
        XCTAssertEqual(counted[.biceps], 2)
        XCTAssertNil(counted[.rearDelts], "vertical pulls don't count for rear delts")
        XCTAssertNil(counted[.hamstrings])
        XCTAssertEqual(MuscleMap().unmapped(in: [session]), ["sled-push"])
    }

    func testWeeklySetsFollowTheMondayGrid() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let sessions = [
            Session(date: date("2026-08-27"), exercises: [entry("squat", 5)]),   // last week
            Session(date: date("2026-09-01"), exercises: [entry("squat", 3)]),   // this week
            Session(date: date("2026-09-02"), exercises: [entry("leg-curl", 4)]),
        ]
        let weeks = MuscleMap().weeklySets(weeks: 2, endingOn: date("2026-09-02"), calendar: utc, in: sessions)
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0][.quads], 5)
        XCTAssertEqual(weeks[1][.quads], 3)
        XCTAssertEqual(weeks[1][.hamstrings], 4)
        XCTAssertNil(weeks[0][.hamstrings])
    }

    func testMuscleReviewReadsAsAWeeklyTable() {
        let weekly: [MuscleMap.Credits] = [[.quads: 9, .back: 6], [.quads: 12, .back: 4.5]]
        let text = CoachContext.muscleReview(weekly: weekly, unmapped: ["sled-push"])!
        XCTAssertTrue(text.hasPrefix("SETS PER MUSCLE."), text)
        XCTAssertTrue(text.contains("Columns: last week · this week."), text)
        XCTAssertTrue(text.contains("quads: 9 · 12"), text)
        XCTAssertTrue(text.contains("back: 6 · 4.5"), text)
        XCTAssertFalse(text.contains("chest"), "muscles with no sets stay out")
        XCTAssertTrue(text.contains("sled-push"), text)
        XCTAssertNil(CoachContext.muscleReview(weekly: [[:], [:]], unmapped: []))
    }

    func testEveryLibraryLiftIsMapped() {
        // The built-in table must cover the picker's own catalogue, or a lift
        // you chose from a list would show as unmapped.
        let library = ["squat", "front-squat", "romanian-deadlift", "deadlift", "leg-press", "leg-curl",
                       "leg-extension", "lunge", "hip-thrust", "calf-raise", "bench-press",
                       "incline-bench-press", "close-grip-bench-press", "over-head-press", "dips",
                       "tricep-pushdown", "lateral-raise", "barbell-row", "seal-row", "upright-row",
                       "pull-ups", "chin-ups", "lat-pulldown", "face-pull", "dumbbell-curl", "hammer-curl",
                       "plank", "hanging-leg-raise"]
        for name in library {
            XCTAssertNotNil(MuscleMap().credits(for: name), name)
        }
    }
}
