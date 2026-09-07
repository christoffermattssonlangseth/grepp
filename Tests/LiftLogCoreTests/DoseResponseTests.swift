import XCTest
@testable import LiftLogCore

final class DoseResponseTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }
    private func day(_ d: String, squat kg: Double, sets: Int = 3, extra: [ExerciseEntry] = []) -> Session {
        Session(date: date(d), exercises: [
            ExerciseEntry(name: "squat", sets: Array(repeating: WorkSet(weight: kg, added: nil, reps: 5), count: sets)),
        ] + extra)
    }

    // Eight weeks ending Sunday 6 Sep 2026: Mondays 13 Jul … 31 Aug.

    func testProgressingReadsTheLatestBestAgainstEarlierWeeks() {
        let sessions = [
            day("2026-08-04", squat: 100), day("2026-08-11", squat: 102.5),
            day("2026-08-18", squat: 105), day("2026-08-25", squat: 107.5),
        ]
        let dose = DoseResponse.make(for: "squat", in: sessions, map: MuscleMap(), endingOn: date("2026-09-06"), calendar: utc)!
        XCTAssertEqual(dose.muscle, .quads)
        XCTAssertEqual(dose.metric, .topSet)
        XCTAssertEqual(dose.weeks.count, 8)
        guard case .progressing(let delta, let own, let sets) = dose.verdict else { return XCTFail("\(dose.verdict)") }
        XCTAssertEqual(delta, 7.5)
        XCTAssertEqual(own, 3)
        XCTAssertEqual(sets, 3, "three squat sets a week is three quad sets")
        XCTAssertEqual(dose.weeks.last { $0.best != nil }?.liftSets, 3)
        XCTAssertTrue(dose.summary.hasPrefix("Progressing: +7.5 kg"), dose.summary)
        XCTAssertTrue(dose.summary.contains("3 squat sets a week (3 for quads in all)"), dose.summary)
    }

    func testFlatAtLowVolumeNamesVolumeAsTheLever() {
        let sessions = [
            day("2026-08-04", squat: 100), day("2026-08-11", squat: 100),
            day("2026-08-18", squat: 100), day("2026-08-25", squat: 100),
        ]
        let dose = DoseResponse.make(for: "squat", in: sessions, map: MuscleMap(), endingOn: date("2026-09-06"), calendar: utc)!
        guard case .stalledLow(let weeks, _, _) = dose.verdict else { return XCTFail("\(dose.verdict)") }
        XCTAssertEqual(weeks, 3)
        XCTAssertTrue(dose.summary.contains("Volume is a lever: another squat set"), dose.summary)
    }

    func testFlatInsideTheBandDoesNotAskForMoreSets() {
        // Ten squat sets plus leg press: quads well inside 10–20.
        let press = ExerciseEntry(name: "leg-press", sets: Array(repeating: WorkSet(weight: 200, added: nil, reps: 10), count: 4))
        let sessions = [
            day("2026-08-04", squat: 100, sets: 8, extra: [press]), day("2026-08-11", squat: 100, sets: 8, extra: [press]),
            day("2026-08-18", squat: 100, sets: 8, extra: [press]), day("2026-08-25", squat: 100, sets: 8, extra: [press]),
        ]
        let dose = DoseResponse.make(for: "squat", in: sessions, map: MuscleMap(), endingOn: date("2026-09-06"), calendar: utc)!
        guard case .stalledMid(_, let own, let all) = dose.verdict else { return XCTFail("\(dose.verdict)") }
        XCTAssertEqual(own, 8, "the lift's own sets")
        XCTAssertEqual(all, 12, "plus the leg press for quads")
        XCTAssertTrue(dose.summary.contains("8 squat sets a week (12 for quads in all)"), dose.summary)
        XCTAssertTrue(dose.summary.contains("inside the band"), dose.summary)
    }

    func testTooEarlyWithUnderThreeWeeksAndNilForUnmappedOrAbsentLifts() {
        let sessions = [day("2026-08-18", squat: 100), day("2026-08-25", squat: 105)]
        XCTAssertEqual(DoseResponse.make(for: "squat", in: sessions, map: MuscleMap(), endingOn: date("2026-09-06"), calendar: utc)?.verdict, .tooEarly)
        XCTAssertNil(DoseResponse.make(for: "sled-push", in: sessions, map: MuscleMap(), endingOn: date("2026-09-06"), calendar: utc), "unmapped")
        XCTAssertNil(DoseResponse.make(for: "bench-press", in: sessions, map: MuscleMap(), endingOn: date("2026-09-06"), calendar: utc), "never done")
    }
}
