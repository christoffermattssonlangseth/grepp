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

    // MARK: - two lines of one lift on a day

    private let backOff = "2026-09-07 squat 100x5 100x5\n2026-09-07 bench 60x8\n2026-09-07 squat 80x8 80x8\n"

    private func ref(_ base: [Session], _ index: Int) -> LineRef {
        LineRef(base[0].exercises[index], in: base[0])
    }

    func testEditingTheSecondLineReplacesOnlyIt() {
        var base = WorkoutParser.parse(backOff)
        let target = ref(base, 2)
        XCTAssertEqual(target.occurrence, 1)
        WorkoutParser.merge(entry("squat", [WorkSet(weight: 80, added: nil, reps: 10)]), on: date("2026-09-07"),
                            replacing: target, into: &base)
        XCTAssertEqual(WorkoutParser.serialize(base),
                       "2026-09-07 squat 100x5 100x5\n2026-09-07 bench 60x8\n2026-09-07 squat 80x10\n")
    }

    func testDeletingOneLineLeavesTheOther() {
        var base = WorkoutParser.parse(backOff)
        WorkoutParser.apply(PendingWrite(operation: .delete(name: "squat"), date: date("2026-09-07"), message: "d",
                                         target: ref(base, 0)), to: &base)
        XCTAssertEqual(WorkoutParser.serialize(base), "2026-09-07 bench 60x8\n2026-09-07 squat 80x8 80x8\n")
    }

    func testMovingOneLineMovesOnlyIt() {
        var base = WorkoutParser.parse(backOff)
        WorkoutParser.apply(PendingWrite(operation: .move(name: "squat", to: date("2026-09-08")), date: date("2026-09-07"),
                                         message: "m", target: ref(base, 2)), to: &base)
        XCTAssertEqual(base.map(\.dateString), ["2026-09-07", "2026-09-08"])
        XCTAssertEqual(base[0].exercises.map(\.name), ["squat", "bench"])
        XCTAssertEqual(base[0].exercises[0].sets.first?.weight, 100)
        XCTAssertEqual(base[1].exercises.map { $0.sets.first?.weight }, [80])
    }

    func testMovingADayKeepsBothLinesOfALift() {
        var base = WorkoutParser.parse(backOff)
        WorkoutParser.move(nil, on: date("2026-09-07"), to: date("2026-09-09"), in: &base)
        XCTAssertEqual(base.count, 1)
        XCTAssertEqual(base[0].exercises.map(\.name), ["squat", "bench", "squat"], "two squat lines, not one")
    }

    func testARefFindsItsLineAfterTheFileShifted() {
        var base = WorkoutParser.parse(backOff)
        let target = ref(base, 2)
        // Another device dropped the first squat line: the back-off line is
        // now the only one, found by its text.
        base = WorkoutParser.parse("2026-09-07 bench 60x8\n2026-09-07 squat 80x8 80x8\n")
        XCTAssertEqual(target.index(in: base[0].exercises), 1)
    }

    func testAStaleRefAddsRatherThanOverwrites() {
        var base = WorkoutParser.parse("2026-09-07 squat 100x5\n")
        let gone = LineRef(day: "2026-09-07", name: "squat", text: "2026-09-07 squat 80x8", occurrence: 1)
        WorkoutParser.merge(entry("squat", [WorkSet(weight: 80, added: nil, reps: 10)]), on: date("2026-09-07"),
                            replacing: gone, into: &base)
        XCTAssertEqual(base[0].exercises.count, 2, "the line the lifter didn't pick is not written over")
    }

    // MARK: - days, not instants

    func testAQueuedWriteKeepsItsDayAcrossTimeZones() throws {
        let write = PendingWrite(operation: .move(name: nil, to: date("2026-08-01")), date: date("2026-08-02"), message: "m")
        let json = String(data: try JSONEncoder().encode(write), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"day\":\"2026-08-02\""), json)
        XCTAssertTrue(json.contains("\"toDay\":\"2026-08-01\""), json)
        XCTAssertEqual(write.day, "2026-08-02")
    }

    func testAQueueSavedBeforeDaysWereTextStillLoads() throws {
        let day = date("2026-08-02").timeIntervalSinceReferenceDate
        let target = date("2026-08-01").timeIntervalSinceReferenceDate
        let legacy = """
        [{"id":"\(UUID().uuidString)","operation":{"move":{"name":"squat","to":\(target)}},"date":\(day),"message":"m"},
         {"id":"\(UUID().uuidString)","operation":{"upsert":{"_0":{"id":"\(UUID().uuidString)","name":"bench","sets":[{"id":"\(UUID().uuidString)","weight":60,"reps":8}]}}},"date":\(day),"message":"u"},
         {"id":"\(UUID().uuidString)","operation":{"delete":{"name":"row"}},"date":\(day),"message":"d"}]
        """
        let decoded = try JSONDecoder().decode([PendingWrite].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.map(\.day), ["2026-08-02", "2026-08-02", "2026-08-02"])
        XCTAssertEqual(decoded[0].operation, .move(name: "squat", toDay: "2026-08-01"))
        XCTAssertEqual(decoded[1].exerciseName, "bench")
        XCTAssertNil(decoded[0].target)
    }

    func testATargetedWriteRoundTrips() throws {
        let base = WorkoutParser.parse(backOff)
        let write = PendingWrite(entry: entry("squat", [WorkSet(weight: 80, added: nil, reps: 10)]),
                                 date: date("2026-09-07"), message: "e", replacing: ref(base, 2))
        let decoded = try JSONDecoder().decode(PendingWrite.self, from: try JSONEncoder().encode(write))
        XCTAssertEqual(decoded, write)
        XCTAssertEqual(decoded.target?.occurrence, 1)
    }
}
