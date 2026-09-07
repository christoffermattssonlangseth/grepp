import XCTest
@testable import LiftLogCore

final class StravaPostTests: XCTestCase {

    private func session(_ names: [String], sets: Int = 3) -> Session {
        Session(date: Session.dateFormatter.date(from: "2026-09-07")!, exercises: names.map {
            ExerciseEntry(name: $0, sets: Array(repeating: WorkSet(weight: 80, added: nil, reps: 5), count: sets))
        })
    }

    func testNameListsTheFirstThreeLifts() {
        XCTAssertEqual(StravaPost.name(for: session(["squat", "bench-press"])), "Lifting · squat, bench press")
        XCTAssertEqual(StravaPost.name(for: session(["a", "b", "c", "d", "e"])), "Lifting · a, b, c +2")
        XCTAssertEqual(StravaPost.name(for: session([])), "Lifting")
    }

    func testDescriptionIsTheLogLinesThenASummary() {
        let text = StravaPost.description(for: session(["squat", "chin-ups"], sets: 2), elapsed: 32 * 60 + 10)
        XCTAssertEqual(text, """
        squat 80x5 80x5
        chin-ups 80x5 80x5

        2 lifts · 4 sets · 32 min

        Tracked with LiftLog — a plain-text lifting log with a Claude coach
        https://github.com/christoffermattssonlangseth/liftlog
        """)
        XCTAssertTrue(StravaPost.description(for: session(["squat"], sets: 1), elapsed: nil).contains("1 lift · 1 set\n"))
    }

    func testElapsedFallsBackToAnHourWhenUnknownOrSilly() {
        let start = Date()
        XCTAssertEqual(StravaPost.elapsed(start: start, end: start.addingTimeInterval(2000)), 2000)
        XCTAssertEqual(StravaPost.elapsed(start: nil, end: start), 3600)
        XCTAssertEqual(StravaPost.elapsed(start: start, end: start.addingTimeInterval(10)), 3600, "under a minute isn't a session")
        XCTAssertEqual(StravaPost.elapsed(start: start, end: start.addingTimeInterval(9 * 3600)), 3600, "a forgotten clock isn't nine hours")
    }
}
