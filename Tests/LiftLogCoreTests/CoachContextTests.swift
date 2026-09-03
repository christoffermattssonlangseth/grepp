import XCTest
@testable import LiftLogCore

final class CoachContextTests: XCTestCase {

    private func date(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }

    private func session(_ d: String, _ name: String = "squat", _ weight: Double = 100) -> Session {
        Session(date: date(d),
                exercises: [ExerciseEntry(name: name, sets: [WorkSet(weight: weight, added: nil, reps: 5)])])
    }

    // MARK: - excerpt

    func testExcerptOfEmptyLog() {
        let excerpt = CoachContext.excerpt(from: [])
        XCTAssertTrue(excerpt.isEmpty)
        XCTAssertEqual(excerpt.text, "")
        XCTAssertEqual(excerpt.omittedCount, 0)
        XCTAssertNil(excerpt.firstDate)
    }

    func testWholeLogFitsWhenSmall() {
        let sessions = [session("2026-08-01"), session("2026-08-08"), session("2026-08-15")]
        let excerpt = CoachContext.excerpt(from: sessions)
        XCTAssertEqual(excerpt.sessionCount, 3)
        XCTAssertEqual(excerpt.omittedCount, 0)
        XCTAssertEqual(excerpt.firstDate, "2026-08-01")
        XCTAssertEqual(excerpt.lastDate, "2026-08-15")
        XCTAssertEqual(excerpt.text, WorkoutParser.serialize(sessions))
    }

    func testBudgetKeepsTheNewestSessionsAndCountsTheRest() {
        // "2026-08-0N squat 100x5\n" is 23 characters, so a 50-char budget fits two.
        let sessions = (1...9).map { session(String(format: "2026-08-%02d", $0)) }
        let excerpt = CoachContext.excerpt(from: sessions, budget: 50)

        XCTAssertEqual(excerpt.sessionCount, 2)
        XCTAssertEqual(excerpt.omittedCount, 7)
        XCTAssertEqual(excerpt.firstDate, "2026-08-08")
        XCTAssertEqual(excerpt.lastDate, "2026-08-09")
        XCTAssertFalse(excerpt.text.contains("2026-08-07"))
    }

    func testUnsortedInputIsOrderedByDate() {
        let excerpt = CoachContext.excerpt(from: [session("2026-08-15"), session("2026-08-01"), session("2026-08-08")])
        XCTAssertEqual(excerpt.firstDate, "2026-08-01")
        XCTAssertEqual(excerpt.lastDate, "2026-08-15")
        XCTAssertLessThan(excerpt.text.range(of: "2026-08-01")!.lowerBound,
                          excerpt.text.range(of: "2026-08-15")!.lowerBound)
    }

    func testOneOversizedSessionIsStillIncluded() {
        // Never hand the model an empty log just because a single day is long.
        let big = Session(date: date("2026-08-01"),
                          exercises: (1...40).map {
                              ExerciseEntry(name: "lift-\($0)", sets: [WorkSet(weight: 60, added: nil, reps: 5)])
                          })
        let excerpt = CoachContext.excerpt(from: [big], budget: 10)
        XCTAssertEqual(excerpt.sessionCount, 1)
        XCTAssertEqual(excerpt.omittedCount, 0)
        XCTAssertTrue(excerpt.text.contains("lift-40"))
    }

    func testExcerptRoundTripsThroughTheParser() {
        // Whatever we send must still be the documented format, not a lossy summary.
        let sessions = [
            Session(date: date("2026-08-01"), exercises: [
                ExerciseEntry(name: "chin-ups", sets: [WorkSet(weight: nil, added: nil, reps: 6),
                                                       WorkSet(weight: nil, added: 5, reps: 4)]),
            ]),
            session("2026-08-08", "deadlift", 82.5),
        ]
        let reparsed = WorkoutParser.parse(CoachContext.excerpt(from: sessions).text)
        XCTAssertEqual(reparsed.map(\.dateString), ["2026-08-01", "2026-08-08"])
        XCTAssertEqual(reparsed[0].exercises[0].sets.map(\.token), ["bwx6", "bw+5x4"])
        XCTAssertEqual(reparsed[1].exercises[0].sets.map(\.token), ["82.5x5"])
    }

    // MARK: - notes

    func testNoteReportsCoverageAndOmissions() {
        let full = CoachContext.excerpt(from: [session("2026-08-01"), session("2026-08-08")])
        XCTAssertEqual(full.note, "Context: 2 sessions 2026-08-01 → 2026-08-08.")

        let trimmed = CoachContext.excerpt(from: (1...9).map { session(String(format: "2026-08-%02d", $0)) },
                                           budget: 50)
        XCTAssertTrue(trimmed.note.contains("7 older omitted"), trimmed.note)

        XCTAssertEqual(CoachContext.excerpt(from: []).note, "No training logged yet.")
    }

    // MARK: - instructions

    func testInstructionsCarryTheLogAndTheFormatKey() {
        let excerpt = CoachContext.excerpt(from: [session("2026-08-01", "squat", 100)])
        let text = CoachContext.instructions(for: excerpt, today: date("2026-08-03"))

        XCTAssertTrue(text.contains("2026-08-01 squat 100x5"))
        XCTAssertTrue(text.contains("<training-log>"))
        XCTAssertTrue(text.contains("</training-log>"))
        XCTAssertTrue(text.contains("bw+5x6"), "the bodyweight tokens need explaining")
        XCTAssertTrue(text.contains("Today is 2026-08-03"))
        XCTAssertTrue(text.contains("the single recorded session, on 2026-08-01"))
    }

    func testInstructionsSayWhenHistoryWasTruncated() {
        let excerpt = CoachContext.excerpt(from: (1...9).map { session(String(format: "2026-08-%02d", $0)) },
                                           budget: 50)
        let text = CoachContext.instructions(for: excerpt, today: date("2026-08-10"))
        XCTAssertTrue(text.contains("7 older sessions exist but were left out"), text)
    }

    func testInstructionsHandleAnEmptyLog() {
        let text = CoachContext.instructions(for: CoachContext.excerpt(from: []), today: date("2026-08-10"))
        XCTAssertTrue(text.contains("The log is empty"))
        XCTAssertFalse(text.contains("<training-log>\n2"), "no session lines to include")
    }
}
