import XCTest
@testable import LiftLogCore

final class WorkoutParserTests: XCTestCase {

    // MARK: - parseSet

    func testParseSetWeighted() {
        let set = WorkoutParser.parseSet("82.5x8")
        XCTAssertEqual(set?.weight, 82.5)
        XCTAssertNil(set?.added)
        XCTAssertEqual(set?.reps, 8)
        XCTAssertFalse(set?.isBodyweight ?? true)
    }

    func testParseSetBodyweight() {
        let set = WorkoutParser.parseSet("bwx6")
        XCTAssertNil(set?.weight)
        XCTAssertNil(set?.added)
        XCTAssertEqual(set?.reps, 6)
        XCTAssertTrue(set?.isBodyweight ?? false)
    }

    func testParseSetBodyweightPlusAddedLoad() {
        let set = WorkoutParser.parseSet("bw+5x8")
        XCTAssertNil(set?.weight)
        XCTAssertEqual(set?.added, 5)
        XCTAssertEqual(set?.reps, 8)
        XCTAssertTrue(set?.isBodyweight ?? false)   // still a bodyweight movement
    }

    func testParseSetRejectsGarbage() {
        for token in ["", "82.5", "x8", "abc", "bw+xx8"] {
            XCTAssertNil(WorkoutParser.parseSet(token), "expected nil for \(token)")
        }
    }

    // MARK: - token round-trip

    func testTokenSerialization() {
        XCTAssertEqual(WorkSet(weight: 82.5, added: nil, reps: 8).token, "82.5x8")
        XCTAssertEqual(WorkSet(weight: 100, added: nil, reps: 5).token, "100x5")   // trailing .0 stripped
        XCTAssertEqual(WorkSet(weight: nil, added: nil, reps: 6).token, "bwx6")
        XCTAssertEqual(WorkSet(weight: nil, added: 5, reps: 8).token, "bw+5x8")
        XCTAssertEqual(WorkSet(weight: nil, added: 0, reps: 6).token, "bwx6")      // +0 collapses to bw
    }

    func testFractionalWeightFormatsToOneDecimal() {
        XCTAssertEqual(WorkSet(weight: 82.5, added: nil, reps: 8).token, "82.5x8")
        // A messy float rounds cleanly instead of leaking "82.50000001".
        XCTAssertEqual(WorkSet(weight: 82.50000001, added: nil, reps: 8).token, "82.5x8")
    }

    // MARK: - parse / serialize

    private let sample = """
    2026-08-01 squat 80x8 80x8 80x8
    2026-08-01 chin-ups bwx6 bw+5x6

    2026-08-03 deadlift 100x5
    """

    func testParseGroupsLinesByDate() {
        let sessions = WorkoutParser.parse(sample)
        XCTAssertEqual(sessions.count, 2)

        let day1 = sessions[0]
        XCTAssertEqual(day1.dateString, "2026-08-01")
        XCTAssertEqual(day1.exercises.map(\.name), ["squat", "chin-ups"])
        XCTAssertEqual(day1.exercises[0].sets.count, 3)
        XCTAssertEqual(day1.exercises[1].sets[1].added, 5)

        XCTAssertEqual(sessions[1].exercises.first?.name, "deadlift")
    }

    func testParseSkipsMalformedLines() {
        let text = "not a workout line\n2026-08-01 squat 80x8\n2026-08-01 squat\n"
        let sessions = WorkoutParser.parse(text)
        XCTAssertEqual(sessions.count, 1)
        // The line with no valid sets is dropped; the one good line survives.
        XCTAssertEqual(sessions[0].exercises.count, 1)
        XCTAssertEqual(sessions[0].exercises[0].sets.count, 1)
    }

    func testSerializeIsSortedAndSeparatedByBlankLines() {
        let sessions = WorkoutParser.parse(sample)
        let out = WorkoutParser.serialize(sessions)
        XCTAssertEqual(out, sample + "\n")   // serialize appends a trailing newline
    }

    func testParseSerializeRoundTripIsStable() {
        let once = WorkoutParser.serialize(WorkoutParser.parse(sample))
        let twice = WorkoutParser.serialize(WorkoutParser.parse(once))
        XCTAssertEqual(once, twice)
    }

    // MARK: - lastEntry

    func testLastEntryFindsMostRecentPriorSession() {
        let sessions = WorkoutParser.parse(sample)
        let cutoff = Session.dateFormatter.date(from: "2026-08-05")!
        let last = WorkoutParser.lastEntry(for: "squat", in: sessions, before: cutoff)
        XCTAssertEqual(last?.sets.count, 3)

        // Nothing before the first squat session.
        let early = Session.dateFormatter.date(from: "2026-07-01")!
        XCTAssertNil(WorkoutParser.lastEntry(for: "squat", in: sessions, before: early))
    }

    // MARK: - nothing lost quietly

    func testWindowsLineEndingsAndABOMDontEatTheLastSet() {
        let text = "\u{FEFF}2026-09-01 squat 100x5 100x5\r\n2026-09-01 bench 60x8\r\n"
        let sessions = WorkoutParser.parse(text)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].exercises.map(\.name), ["squat", "bench"])
        XCTAssertEqual(sessions[0].exercises[0].sets.count, 2)
        XCTAssertEqual(sessions[0].exercises[1].sets.count, 1)
        XCTAssertTrue(WorkoutParser.unreadableLines(in: text).isEmpty)
    }

    func testAMultiWordNameIsOneLiftWithDashes() {
        let sessions = WorkoutParser.parse("2026-09-01 bench press 60x5 60x5\n2026-09-01 leg press 100x10")
        XCTAssertEqual(sessions[0].exercises.map(\.name), ["bench-press", "leg-press"])
        XCTAssertEqual(sessions[0].exercises[0].sets.count, 2)
    }

    func testUnreadableLinesAreNamedNotDropped() {
        let text = "2026-09-01 squat 100x5\n\n# a note\n2026-9-1 bench 60x8\n2026-09-02 row 50x\n2026-09-02 row 50x8"
        let bad = WorkoutParser.unreadableLines(in: text)
        XCTAssertEqual(bad.map(\.number), [3, 4, 5])
        XCTAssertEqual(bad[0].text, "# a note")
        XCTAssertEqual(WorkoutParser.parse(text).flatMap(\.exercises).map(\.name), ["squat", "row"])
    }
}
