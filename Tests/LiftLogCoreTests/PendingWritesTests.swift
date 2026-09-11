import XCTest
@testable import LiftLogCore

final class PendingWritesTests: XCTestCase {

    private func date(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }

    private func entry(_ name: String, _ sets: [WorkSet]) -> ExerciseEntry {
        ExerciseEntry(name: name, sets: sets)
    }

    // MARK: - merge

    func testMergeAddsNewDateSorted() {
        var base = [Session(date: date("2026-08-10"), exercises: [entry("squat", [WorkSet(weight: 100, added: nil, reps: 5)])])]
        WorkoutParser.merge(entry("bench", [WorkSet(weight: 60, added: nil, reps: 8)]), on: date("2026-08-01"), into: &base)

        XCTAssertEqual(base.count, 2)
        XCTAssertEqual(base.map(\.dateString), ["2026-08-01", "2026-08-10"])  // sorted ascending
    }

    func testMergeAppendsExerciseToExistingDate() {
        var base = [Session(date: date("2026-08-01"), exercises: [entry("squat", [WorkSet(weight: 100, added: nil, reps: 5)])])]
        WorkoutParser.merge(entry("bench", [WorkSet(weight: 60, added: nil, reps: 8)]), on: date("2026-08-01"), into: &base)

        XCTAssertEqual(base.count, 1)
        XCTAssertEqual(base[0].exercises.map(\.name), ["squat", "bench"])
    }

    func testMergeReplacesSameExerciseSameDayCaseInsensitively() {
        var base = [Session(date: date("2026-08-01"), exercises: [entry("Squat", [WorkSet(weight: 100, added: nil, reps: 5)])])]
        WorkoutParser.merge(entry("squat", [WorkSet(weight: 110, added: nil, reps: 3)]), on: date("2026-08-01"), into: &base)

        XCTAssertEqual(base[0].exercises.count, 1)              // replaced, not duplicated
        XCTAssertEqual(base[0].exercises[0].sets.first?.weight, 110)
    }

    // MARK: - applying a queue

    func testApplyingReplaysWritesInOrder() {
        let writes = [
            PendingWrite(entry: entry("squat", [WorkSet(weight: 100, added: nil, reps: 5)]), date: date("2026-08-01"), message: "a"),
            PendingWrite(entry: entry("bench", [WorkSet(weight: 60, added: nil, reps: 8)]), date: date("2026-08-01"), message: "b"),
            PendingWrite(entry: entry("squat", [WorkSet(weight: 105, added: nil, reps: 5)]), date: date("2026-08-01"), message: "c"),
        ]
        let result = WorkoutParser.applying(writes, to: [])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].exercises.map(\.name), ["squat", "bench"])
        XCTAssertEqual(result[0].exercises[0].sets.first?.weight, 105)  // last squat write wins
    }

    func testApplyingLayersOnTopOfExistingSessions() {
        let existing = WorkoutParser.parse("2026-08-01 squat 100x5\n")
        let writes = [PendingWrite(entry: entry("deadlift", [WorkSet(weight: 140, added: nil, reps: 3)]),
                                   date: date("2026-08-02"), message: "d")]
        let result = WorkoutParser.applying(writes, to: existing)

        XCTAssertEqual(result.map(\.dateString), ["2026-08-01", "2026-08-02"])
    }

    // MARK: - remove / delete

    func testRemoveDropsExerciseAndEmptyDay() {
        var base = WorkoutParser.parse("2026-08-01 squat 100x5\n2026-08-01 bench 60x8\n")
        WorkoutParser.remove("squat", on: date("2026-08-01"), from: &base)
        XCTAssertEqual(base[0].exercises.map(\.name), ["bench"])

        // Removing the last exercise drops the whole session.
        WorkoutParser.remove("BENCH", on: date("2026-08-01"), from: &base)  // case-insensitive
        XCTAssertTrue(base.isEmpty)
    }

    func testRemoveMissingIsNoOp() {
        var base = WorkoutParser.parse("2026-08-01 squat 100x5\n")
        WorkoutParser.remove("deadlift", on: date("2026-08-01"), from: &base)
        WorkoutParser.remove("squat", on: date("2026-09-09"), from: &base)  // wrong day
        XCTAssertEqual(base.count, 1)
        XCTAssertEqual(base[0].exercises.count, 1)
    }

    func testApplyingMixesUpsertsAndDeletes() {
        let writes = [
            PendingWrite(entry: entry("squat", [WorkSet(weight: 100, added: nil, reps: 5)]), date: date("2026-08-01"), message: "a"),
            PendingWrite(entry: entry("bench", [WorkSet(weight: 60, added: nil, reps: 8)]), date: date("2026-08-01"), message: "b"),
            PendingWrite(operation: .delete(name: "squat"), date: date("2026-08-01"), message: "c"),
        ]
        let result = WorkoutParser.applying(writes, to: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].exercises.map(\.name), ["bench"])
    }

    // MARK: - Codable round-trip (queue is persisted as JSON)

    // MARK: - move

    private func twoDays() -> [Session] {
        [Session(date: date("2026-09-07"), exercises: [
            entry("squat", [WorkSet(weight: 100, added: nil, reps: 5)]),
            entry("bench", [WorkSet(weight: 60, added: nil, reps: 8)]),
         ]),
         Session(date: date("2026-09-08"), exercises: [
            entry("deadlift", [WorkSet(weight: 140, added: nil, reps: 5)]),
         ])]
    }

    func testMoveOneExerciseToAnotherDay() {
        var base = twoDays()
        WorkoutParser.move("Bench", on: date("2026-09-07"), to: date("2026-09-08"), in: &base)
        XCTAssertEqual(base.map(\.dateString), ["2026-09-07", "2026-09-08"])
        XCTAssertEqual(base[0].exercises.map(\.name), ["squat"])
        XCTAssertEqual(base[1].exercises.map(\.name), ["deadlift", "bench"], "appended to the day it joins")
    }

    func testMoveWholeDayMergesAndDropsTheEmptyDay() {
        var base = twoDays()
        WorkoutParser.move(nil, on: date("2026-09-08"), to: date("2026-09-07"), in: &base)
        XCTAssertEqual(base.map(\.dateString), ["2026-09-07"])
        XCTAssertEqual(base[0].exercises.map(\.name), ["squat", "bench", "deadlift"])
    }

    func testMoveToNewDateCreatesItInOrder() {
        var base = twoDays()
        WorkoutParser.move(nil, on: date("2026-09-08"), to: date("2026-09-01"), in: &base)
        XCTAssertEqual(base.map(\.dateString), ["2026-09-01", "2026-09-07"])
        XCTAssertEqual(base[0].exercises.map(\.name), ["deadlift"])
    }

    func testMoveReplacesSameLiftOnTargetDay() {
        var base = twoDays()
        base[1].exercises.append(entry("squat", [WorkSet(weight: 90, added: nil, reps: 5)]))
        WorkoutParser.move("squat", on: date("2026-09-07"), to: date("2026-09-08"), in: &base)
        XCTAssertEqual(base[1].exercises.map(\.name), ["deadlift", "squat"], "one squat, not two")
        XCTAssertEqual(base[1].exercises[1].sets.first?.weight, 100, "the moved one wins")
    }

    func testMoveSameDayOrMissingIsNoOp() {
        var base = twoDays()
        let before = base
        WorkoutParser.move("squat", on: date("2026-09-07"), to: date("2026-09-07"), in: &base)
        WorkoutParser.move("curl", on: date("2026-09-07"), to: date("2026-09-08"), in: &base)
        WorkoutParser.move(nil, on: date("2026-09-09"), to: date("2026-09-08"), in: &base)
        XCTAssertEqual(base, before)
    }

    func testMergeAddsWholeSessionsOntoTheirDays() {
        var base = twoDays()
        let brought = [
            Session(date: date("2026-09-01"), exercises: [entry("squat", [WorkSet(weight: 90, added: nil, reps: 5)])]),
            Session(date: date("2026-09-07"), exercises: [entry("deadlift", [WorkSet(weight: 130, added: nil, reps: 5)])]),
        ]
        WorkoutParser.apply(PendingWrite(operation: .merge(sessions: brought), date: date("2026-09-07"), message: "Add 2 sessions"), to: &base)
        XCTAssertEqual(base.map(\.dateString), ["2026-09-01", "2026-09-07", "2026-09-08"])
        XCTAssertEqual(base[1].exercises.map(\.name), ["squat", "bench", "deadlift"], "joins the day already there")
    }

    func testPendingWriteCodableRoundTrip() throws {
        let original = [
            PendingWrite(entry: entry("chin-ups", [WorkSet(weight: nil, added: 5, reps: 6)]),
                         date: date("2026-08-01"), message: "Log chin-ups 2026-08-01"),
            PendingWrite(operation: .delete(name: "squat"),
                         date: date("2026-08-02"), message: "Delete squat 2026-08-02"),
            PendingWrite(operation: .move(name: nil, to: date("2026-08-01")),
                         date: date("2026-08-02"), message: "Move 2026-08-02 to 2026-08-01"),
            PendingWrite(operation: .merge(sessions: [Session(date: date("2026-07-30"), exercises: [entry("squat", [WorkSet(weight: 80, added: nil, reps: 5)])])]),
                         date: date("2026-07-30"), message: "Add 1 session (2026-07-30)"),
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([PendingWrite].self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
