import XCTest
@testable import LiftLogCore

final class AnalyticsTests: XCTestCase {

    private func date(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }

    private func session(_ d: String, _ name: String, _ sets: [WorkSet]) -> Session {
        Session(date: date(d), exercises: [ExerciseEntry(name: name, sets: sets)])
    }

    // MARK: - classification

    func testIsBodyweightStaysTrueWithAddedLoad() {
        let sessions = [
            session("2026-08-01", "chin-ups", [WorkSet(weight: nil, added: nil, reps: 6)]),
            session("2026-08-08", "chin-ups", [WorkSet(weight: nil, added: 5, reps: 6)]),
        ]
        XCTAssertTrue(Analytics.isBodyweight("chin-ups", in: sessions))
        XCTAssertTrue(Analytics.hasAddedLoad("chin-ups", in: sessions))
    }

    func testAvailableMetricsByExerciseType() {
        let weighted = [session("2026-08-01", "squat", [WorkSet(weight: 80, added: nil, reps: 8)])]
        XCTAssertEqual(Analytics.availableMetrics("squat", in: weighted), [.topSet, .oneRepMax])

        let pureBW = [session("2026-08-01", "chin-ups", [WorkSet(weight: nil, added: nil, reps: 6)])]
        XCTAssertEqual(Analytics.availableMetrics("chin-ups", in: pureBW), [.maxReps])

        let loadedBW = [session("2026-08-01", "chin-ups", [WorkSet(weight: nil, added: 5, reps: 6)])]
        XCTAssertEqual(Analytics.availableMetrics("chin-ups", in: loadedBW), [.addedLoad, .maxReps])
    }

    // MARK: - records

    private let squat100 = [Session(date: Session.dateFormatter.date(from: "2026-08-01")!,
                                    exercises: [ExerciseEntry(name: "squat", sets: [WorkSet(weight: 100, added: nil, reps: 5)])])]

    func testFirstSetOfANewLiftIsNotARecord() {
        XCTAssertNil(Analytics.record(for: WorkSet(weight: 100, added: nil, reps: 5), exercise: "squat", in: []))
    }

    func testHeavierThanEverIsALoadRecord() {
        XCTAssertEqual(Analytics.record(for: WorkSet(weight: 102.5, added: nil, reps: 1), exercise: "squat", in: squat100), .load)
        XCTAssertNil(Analytics.record(for: WorkSet(weight: 95, added: nil, reps: 10), exercise: "squat", in: squat100),
                     "lighter isn't a record however many reps")
    }

    func testMoreRepsAtTheSameLoadIsARepRecord() {
        XCTAssertEqual(Analytics.record(for: WorkSet(weight: 100, added: nil, reps: 6), exercise: "squat", in: squat100), .reps)
        XCTAssertNil(Analytics.record(for: WorkSet(weight: 100, added: nil, reps: 5), exercise: "squat", in: squat100),
                     "matching isn't beating")
    }

    func testSetsLandedTodayCountAsHistory() {
        let first = WorkSet(weight: 105, added: nil, reps: 5)
        XCTAssertEqual(Analytics.record(for: first, exercise: "squat", in: squat100), .load)
        XCTAssertNil(Analytics.record(for: WorkSet(weight: 105, added: nil, reps: 5), exercise: "squat", in: squat100, plus: [first]),
                     "the second 105x5 today isn't a record just because the first was")
    }

    func testBodyweightRecordsCompareAddedLoadThenReps() {
        let history = [session("2026-08-01", "chin-ups", [WorkSet(weight: nil, added: nil, reps: 8)])]
        XCTAssertEqual(Analytics.record(for: WorkSet(weight: nil, added: 5, reps: 3), exercise: "chin-ups", in: history), .load)
        XCTAssertEqual(Analytics.record(for: WorkSet(weight: nil, added: nil, reps: 9), exercise: "chin-ups", in: history), .reps)
        XCTAssertNil(Analytics.record(for: WorkSet(weight: nil, added: nil, reps: 7), exercise: "chin-ups", in: history))
    }

    func testRecordsMatchTheLiftNameCaseInsensitively() {
        let history = [session("2026-08-01", "Squat", [WorkSet(weight: 100, added: nil, reps: 5)])]
        XCTAssertEqual(Analytics.record(for: WorkSet(weight: 110, added: nil, reps: 1), exercise: "squat", in: history), .load)
    }

    // MARK: - series

    func testTopSetSeriesTakesHeaviestPerSession() {
        let sessions = [
            session("2026-08-01", "squat", [WorkSet(weight: 80, added: nil, reps: 8),
                                            WorkSet(weight: 90, added: nil, reps: 3)]),
            session("2026-08-08", "squat", [WorkSet(weight: 100, added: nil, reps: 5)]),
        ]
        let series = Analytics.series("squat", metric: .topSet, in: sessions)
        XCTAssertEqual(series.map(\.value), [90, 100])
    }

    func testAddedLoadSeriesIsContinuousFromBodyweight() {
        let sessions = [
            session("2026-08-01", "chin-ups", [WorkSet(weight: nil, added: nil, reps: 6)]),
            session("2026-08-08", "chin-ups", [WorkSet(weight: nil, added: 5, reps: 6)]),
            session("2026-08-15", "chin-ups", [WorkSet(weight: nil, added: 7.5, reps: 5)]),
        ]
        let series = Analytics.series("chin-ups", metric: .addedLoad, in: sessions)
        // Pure-bodyweight session plots as 0, so the line runs unbroken.
        XCTAssertEqual(series.map(\.value), [0, 5, 7.5])
    }

    // MARK: - change

    func testChangeReportsDeltaAndPercent() {
        let sessions = [
            session("2026-08-01", "squat", [WorkSet(weight: 80, added: nil, reps: 5)]),
            session("2026-08-15", "squat", [WorkSet(weight: 100, added: nil, reps: 5)]),
        ]
        let series = Analytics.series("squat", metric: .topSet, in: sessions)
        let change = Analytics.change(series)
        XCTAssertEqual(change?.delta, 20)
        XCTAssertEqual(change?.percent ?? 0, 25, accuracy: 0.001)
        XCTAssertTrue(change?.isUp ?? false)
    }

    func testChangeNeedsTwoPoints() {
        let single = [session("2026-08-01", "squat", [WorkSet(weight: 80, added: nil, reps: 5)])]
        let series = Analytics.series("squat", metric: .topSet, in: single)
        XCTAssertNil(Analytics.change(series))
    }

    func testEpleyOneRepMax() {
        XCTAssertEqual(Analytics.epley(weight: 100, reps: 0), 100, accuracy: 0.001)
        XCTAssertEqual(Analytics.epley(weight: 100, reps: 10), 100 * (1 + 10.0 / 30), accuracy: 0.001)
    }
}
