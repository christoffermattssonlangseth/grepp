import XCTest
@testable import LiftLogCore

final class SessionDraftTests: XCTestCase {

    private func draft(sets: [WorkSet], plan: [WorkSet]?) -> SessionDraft {
        SessionDraft(date: Date(), name: "squat", sets: sets, isBodyweight: false,
                     weightText: "", addedText: "", repsText: "", plan: plan, queue: [], restStart: nil)
    }

    func testSameAgainPrefersThePlanThenRepeatsTheLast() {
        let planned = WorkSet(weight: 87.5, added: nil, reps: 5)
        let done = WorkSet(weight: 85, added: nil, reps: 5)
        XCTAssertEqual(draft(sets: [done], plan: [planned, planned]).sameAgainSet?.token, "87.5x5")
        XCTAssertEqual(draft(sets: [done, done], plan: [planned, planned]).sameAgainSet?.token, "85x5",
                       "plan done — repeat the last set")
        XCTAssertEqual(draft(sets: [done], plan: nil).sameAgainSet?.token, "85x5")
        XCTAssertNil(draft(sets: [], plan: nil).sameAgainSet)
        XCTAssertNil(draft(sets: [], plan: nil).nextPlanned)
    }

    func testLoadLabelSpeaksLikeALifter() {
        XCTAssertEqual(WorkSet(weight: 87.5, added: nil, reps: 5).loadLabel, "87.5 kg")
        XCTAssertEqual(WorkSet(weight: nil, added: 5, reps: 5).loadLabel, "BW +5 kg")
        XCTAssertEqual(WorkSet(weight: nil, added: nil, reps: 5).loadLabel, "Bodyweight")
    }


    private let set = WorkSet(weight: 87.5, added: nil, reps: 5)

    func testRoundTripsThroughJSON() throws {
        let draft = SessionDraft(date: Session.dateFormatter.date(from: "2027-01-15")!,   // a day: that is what is kept
                                 name: "squat", sets: [set, set], isBodyweight: false,
                                 weightText: "87.5", addedText: "", repsText: "5",
                                 plan: [set, set, set],
                                 queue: [ExerciseEntry(name: "bench-press", sets: [set])],
                                 restStart: Date(timeIntervalSince1970: 1_800_000_100))
        let data = try JSONEncoder().encode(draft)
        XCTAssertEqual(try JSONDecoder().decode(SessionDraft.self, from: data), draft)
    }

    func testEmptinessIgnoresTypedButUnaddedNumbers() {
        var draft = SessionDraft(date: Date(), name: "", sets: [], isBodyweight: false,
                                 weightText: "87.5", addedText: "", repsText: "5",
                                 plan: nil, queue: [], restStart: nil)
        XCTAssertTrue(draft.isEmpty, "numbers in the fields alone aren't worth restoring")
        draft.name = "squat"
        XCTAssertFalse(draft.isEmpty, "a chosen lift is")
        draft.name = ""
        draft.queue = [ExerciseEntry(name: "bench-press", sets: [set])]
        XCTAssertFalse(draft.isEmpty, "so is a queue still to do")
    }

    func testADraftKeepsItsDayAndWhetherItWasChosen() throws {
        var draft = SessionDraft(date: Session.dateFormatter.date(from: "2026-08-03")!, name: "squat", sets: [set],
                                 isBodyweight: false, weightText: "", addedText: "", repsText: "",
                                 plan: nil, queue: [], restStart: nil)
        draft.dateChosen = true
        let data = try JSONEncoder().encode(draft)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("\"date\":\"2026-08-03\""), "the day, not an instant")
        let back = try JSONDecoder().decode(SessionDraft.self, from: data)
        XCTAssertEqual(back.dateChosen, true)
        XCTAssertEqual(Session.dateFormatter.string(from: back.date), "2026-08-03")
    }

    func testADraftSavedBeforeTheseFieldsStillLoads() throws {
        let legacy = """
        {"date":\(Date().timeIntervalSinceReferenceDate),"name":"squat","sets":[],"isBodyweight":false,
         "weightText":"","addedText":"","repsText":"","queue":[]}
        """
        let draft = try JSONDecoder().decode(SessionDraft.self, from: Data(legacy.utf8))
        XCTAssertNil(draft.dateChosen)
        XCTAssertNil(draft.target)
        XCTAssertEqual(draft.name, "squat")
    }
}
