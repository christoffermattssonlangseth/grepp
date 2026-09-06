import XCTest
@testable import LiftLogCore

final class PlanRecordTests: XCTestCase {

    private func date(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }
    private func sets(_ tokens: String) -> [WorkSet] {
        tokens.split(separator: " ").map { WorkoutParser.parseSet(String($0))! }
    }
    private func entry(_ name: String, _ tokens: String) -> ExerciseEntry {
        ExerciseEntry(name: name, sets: sets(tokens))
    }

    // MARK: - verdicts

    private func verdict(plan: String, did: String) -> String? {
        PlanRecord(prescribed: date("2026-09-06"), name: "squat", plan: sets(plan),
                   done: date("2026-09-06"), sets: sets(did)).verdict
    }

    func testAsPrescribedHasNoVerdict() {
        XCTAssertNil(verdict(plan: "87.5x5 87.5x5 87.5x5", did: "87.5x5 87.5x5 87.5x5"))
        XCTAssertNil(PlanRecord(prescribed: date("2026-09-06"), name: "squat", plan: sets("87.5x5")).verdict,
                     "not done yet — nothing to judge")
    }

    func testRepsShortAndSetsShort() {
        XCTAssertEqual(verdict(plan: "87.5x5 87.5x5 87.5x5", did: "87.5x5 87.5x5 87.5x4"), "1 rep short")
        XCTAssertEqual(verdict(plan: "87.5x5 87.5x5 87.5x5", did: "87.5x5 87.5x5"), "1 set short")
        XCTAssertEqual(verdict(plan: "87.5x5 87.5x5 87.5x5", did: "87.5x5"), "2 sets short")
    }

    func testHeavierAndLighterComeFirst() {
        XCTAssertEqual(verdict(plan: "87.5x5 87.5x5 87.5x5", did: "90x5 90x5 90x5"), "heavier")
        XCTAssertEqual(verdict(plan: "87.5x5 87.5x5 87.5x5", did: "85x5 85x5 85x3"), "lighter, 2 reps short")
        XCTAssertEqual(verdict(plan: "87.5x5 87.5x5 87.5x5", did: "90x5 90x5 90x5 90x5"), "heavier, 1 extra set")
    }

    func testBodyweightComparesAddedLoad() {
        let plan = sets("bw+5x6 bw+5x6")
        let heavier = PlanRecord(prescribed: date("2026-09-06"), name: "chin-ups", plan: plan,
                                 done: date("2026-09-06"), sets: sets("bw+7.5x6 bw+7.5x6")).verdict
        XCTAssertEqual(heavier, "heavier")
        let over = PlanRecord(prescribed: date("2026-09-06"), name: "chin-ups", plan: plan,
                              done: date("2026-09-06"), sets: sets("bw+5x8 bw+5x6")).verdict
        XCTAssertEqual(over, "2 reps over")
    }

    // MARK: - bookkeeping

    func testPrescribeReplacesAnOpenPlanForTheSameLift() {
        var records: [PlanRecord] = []
        records.prescribe([entry("squat", "85x5 85x5 85x5"), entry("bench", "70x5 70x5 70x5")], on: date("2026-09-05"))
        records.prescribe([entry("Squat", "87.5x5 87.5x5 87.5x5")], on: date("2026-09-06"))
        XCTAssertEqual(records.map(\.name), ["bench", "Squat"])
        XCTAssertEqual(records[1].plan.map(\.token), ["87.5x5", "87.5x5", "87.5x5"])
    }

    func testCompletePinsTheDoneSetsToTheOpenPlan() {
        var records: [PlanRecord] = []
        records.prescribe([entry("squat", "87.5x5 87.5x5 87.5x5")], on: date("2026-09-06"))
        records.complete(entry("squat", "87.5x5 87.5x5 87.5x4"), on: date("2026-09-06"))
        XCTAssertEqual(records[0].done, date("2026-09-06"))
        XCTAssertEqual(records[0].verdict, "1 rep short")

        // A second squat day with no plan open leaves the record alone.
        records.complete(entry("squat", "90x5"), on: date("2026-09-08"))
        XCTAssertEqual(records[0].sets.map(\.token), ["87.5x5", "87.5x5", "87.5x4"])
        XCTAssertEqual(records.count, 1)
    }

    func testPruneDropsOldRecordsButKeepsRecentlyDoneOnes() {
        var records: [PlanRecord] = []
        records.prescribe([entry("old", "50x5")], on: date("2026-07-01"))
        records.prescribe([entry("late", "50x5")], on: date("2026-07-01"))
        records.complete(entry("late", "50x5"), on: date("2026-09-01"))
        records.prescribe([entry("new", "50x5")], on: date("2026-09-05"))
        records.prune(before: date("2026-08-15"))
        XCTAssertEqual(records.map(\.name), ["late", "new"])
    }

    // MARK: - what the coach reads

    func testPlanReviewListsDoneAndOpenPlans() {
        var records: [PlanRecord] = []
        records.prescribe([entry("squat", "87.5x5 87.5x5 87.5x5"), entry("bench", "70x5 70x5 70x5")],
                          on: date("2026-09-06"))
        records.complete(entry("squat", "87.5x5 87.5x5 87.5x4"), on: date("2026-09-06"))
        let now = date("2026-09-06").addingTimeInterval(12 * 3600)

        let text = CoachContext.planReview(records, now: now)!
        XCTAssertTrue(text.hasPrefix("PRESCRIBED VS DONE."), text)
        XCTAssertTrue(text.contains("2026-09-06 squat — prescribed 87.5x5 87.5x5 87.5x5 · did 87.5x5 87.5x5 87.5x4 (1 rep short)"), text)
        XCTAssertTrue(text.contains("bench — prescribed 70x5 70x5 70x5 on 2026-09-06 · not done yet"), text)
    }

    func testPlanReviewIsNilWithNothingRecent() {
        var records: [PlanRecord] = []
        records.prescribe([entry("squat", "80x5")], on: date("2026-06-01"))
        XCTAssertNil(CoachContext.planReview(records, now: date("2026-09-06")))
        XCTAssertNil(CoachContext.planReview([], now: date("2026-09-06")))
    }

    func testLiveNoteJoinsSessionAndPlans() {
        var records: [PlanRecord] = []
        records.prescribe([entry("squat", "87.5x5 87.5x5 87.5x5")], on: date("2026-09-06"))
        let draft = SessionDraft(date: date("2026-09-06"), name: "squat", sets: sets("87.5x5"),
                                 isBodyweight: false, weightText: "", addedText: "", repsText: "",
                                 plan: sets("87.5x5 87.5x5 87.5x5"), queue: [], restStart: nil)
        let text = CoachContext.liveNote(draft: draft, plans: records, now: date("2026-09-06"))!
        XCTAssertTrue(text.contains("RIGHT NOW."), text)
        XCTAssertTrue(text.contains("PRESCRIBED VS DONE."), text)
        XCTAssertNil(CoachContext.liveNote(draft: nil, plans: [], now: date("2026-09-06")))
    }
}
