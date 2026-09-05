import XCTest
@testable import LiftLogCore

final class SessionDraftTests: XCTestCase {

    private let set = WorkSet(weight: 87.5, added: nil, reps: 5)

    func testRoundTripsThroughJSON() throws {
        let draft = SessionDraft(date: Date(timeIntervalSince1970: 1_800_000_000),
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
}
