import XCTest
@testable import LiftLogCore

final class ReversePyramidTests: XCTestCase {

    private func entry(_ name: String, _ tokens: String) -> ExerciseEntry {
        ExerciseEntry(name: name, sets: tokens.split(separator: " ").map { WorkoutParser.parseSet(String($0))! })
    }
    private func tokens(_ sets: [WorkSet]?) -> String { (sets ?? []).map(\.token).joined(separator: " ") }

    func testTheLineMarksTheSchemeWithoutJoiningTheName() {
        let a = Programme.parseExercise("deadlift rpt 2x4-6 — top set, then one at −10%")!
        XCTAssertEqual(a.name, "deadlift")
        XCTAssertTrue(a.rpt)
        XCTAssertEqual(a.scheme, "2x4-6")
        XCTAssertEqual(a.setsAndReps?.sets, 2)
        XCTAssertEqual(a.setsAndReps?.reps, 4...6)
        let b = Programme.parseExercise("Bench press 3x6-8 RPT")!
        XCTAssertEqual(b.name, "bench-press")
        XCTAssertTrue(b.rpt)
        let c = Programme.parseExercise("squat 3x5 — add 2.5 kg when all sets hit")!
        XCTAssertFalse(c.rpt)
        XCTAssertEqual(c.setsAndReps?.reps, 5...5)
        XCTAssertNil(Programme.parseExercise("chin-ups 3xAMRAP")!.setsAndReps)
    }

    func testHittingTheRangeStepsTheLoadUpAndBackOffsFollow() {
        let plan = ReversePyramid.plan("squat", sets: 3, reps: 6...8, last: entry("squat", "100x8 90x10 80x12"))
        XCTAssertEqual(tokens(plan), "105x6 95x8 85x10", "5 kg on a squat; back-offs a tenth lighter to the nearest 2.5, two reps more each")
    }

    func testShortOfTheRangeKeepsTheLoadAndAsksForOneMoreRep() {
        let plan = ReversePyramid.plan("bench-press", sets: 3, reps: 6...8, last: entry("bench-press", "80x6 72.5x8 65x10"))
        XCTAssertEqual(tokens(plan), "80x7 72.5x9 65x11")
        let stuck = ReversePyramid.plan("bench-press", sets: 2, reps: 6...8, last: entry("bench-press", "80x3"))
        XCTAssertEqual(tokens(stuck), "80x6 72.5x8", "never below the bottom of the range")
    }

    func testABodyweightLiftStepsTheAddedLoad() {
        let hit = ReversePyramid.plan("chin-ups", sets: 3, reps: 5...7, last: entry("chin-ups", "bw+10x7 bw+7.5x9"))
        XCTAssertEqual(tokens(hit), "bw+12.5x5 bw+10x7 bw+7.5x9")
        let fresh = ReversePyramid.plan("chin-ups", sets: 3, reps: 5...7, last: entry("chin-ups", "bwx5"))
        XCTAssertEqual(tokens(fresh), "bwx6 bwx8 bwx10", "nothing hung on yet: reps climb, load stays at nothing")
    }

    func testTheTopSetIsTheHeaviestNotTheFirst() {
        let plan = ReversePyramid.plan("deadlift", sets: 2, reps: 4...6, last: entry("deadlift", "120x6 140x6"))
        XCTAssertEqual(tokens(plan), "145x4 130x6")
    }

    func testABackOffIsNeverHeavierThanTheTopSetOrClampedToTheBar() {
        let plan = ReversePyramid.plan("curl", sets: 3, reps: 6...8, last: entry("curl", "15x8 15x8"), bar: 20)
        XCTAssertEqual(tokens(plan), "17.5x6 15x8 15x10", "under the bar the number stands; it never rounds up to the bar")
    }

    func testTheDueDayRecognisesALiftUnderAnySpelling() {
        let programme = Programme.parse("""
        ## Day A
        - deadlift rpt 2x4-6
        - barbell-row 3x8-10
        ## Day B
        - bench-press 3x5
        """)
        let sessions = [Session(date: Session.dateFormatter.date(from: "2026-09-10")!, exercises: [
            entry("deadlift", "140x6"), entry("row", "60x10"),
        ])]
        XCTAssertEqual(programme.dueDayIndex(in: sessions), 1)
    }

    func testNoHistoryIsNoPlan() {
        XCTAssertNil(ReversePyramid.plan("squat", sets: 3, reps: 6...8, last: nil))
        XCTAssertEqual(ReversePyramid.increment(for: "Back squat"), 5)
        XCTAssertEqual(ReversePyramid.increment(for: "over-head-press"), 2.5)
    }

    func testADayBecomesASessionAndNamesWhatItCannot() {
        let day = Programme.parse("""
        ## Day A — Pull
        - deadlift rpt 2x4-6
        - barbell-row 3x8-10
        - face-pull 3x15
        """).days[0]
        let sessions = [Session(date: Session.dateFormatter.date(from: "2026-09-10")!, exercises: [
            entry("deadlift", "140x6 125x8"), entry("row", "60x10 60x10 60x9"),
        ])]
        let plan = ReversePyramid.plan(day: day, in: sessions, bar: { _ in 20 }, inventory: .standard)
        XCTAssertEqual(plan.entries.map(\.name), ["deadlift", "row"], "under the log's own spelling, so the history stays one line of lifts")
        XCTAssertEqual(tokens(plan.entries[0].sets), "145x4 130x6")
        XCTAssertEqual(tokens(plan.entries[1].sets), "60x10 60x10 60x9", "a lift without the mark repeats its last session, whatever the log called it")
        XCTAssertEqual(plan.missing, ["face-pull"])
    }

    func testTheStarterReadsAsAProgramme() {
        let programme = Programme.parse(ReversePyramid.starter)
        XCTAssertEqual(programme.days.count, 3)
        XCTAssertEqual(programme.days[0].exercises.filter(\.rpt).map(\.name), ["deadlift", "chin-ups"])
        XCTAssertTrue(programme.days.flatMap(\.exercises).allSatisfy { !$0.rpt || $0.setsAndReps != nil })
    }
}
