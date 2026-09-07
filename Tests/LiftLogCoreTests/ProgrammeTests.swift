import XCTest
@testable import LiftLogCore

final class ProgrammeTests: XCTestCase {

    private let file = """
    # Upper / Lower, 4 days

    Some prose the coach wrote about the plan.

    ## Day A — Lower
    - squat 3x5 — add 2.5 kg when all three sets hit 5
    - romanian-deadlift 3x8–10 — add 2.5 kg once 3x10
    - calf-raise 3x12–15
    - a note that is not a lift

    ## Day B — Upper
    * Bench Press 3x5 — add 2.5 kg when all sets hit
    - chin-ups 3xAMRAP
    """

    func testParsesTitleDaysAndLifts() {
        let p = Programme.parse(file)
        XCTAssertEqual(p.title, "Upper / Lower, 4 days")
        XCTAssertEqual(p.days.map(\.title), ["Day A — Lower", "Day B — Upper"])
        XCTAssertEqual(p.days[0].exercises.map(\.name), ["squat", "romanian-deadlift", "calf-raise"])
        XCTAssertEqual(p.days[0].exercises[0].scheme, "3x5")
        XCTAssertEqual(p.days[0].exercises[0].note, "add 2.5 kg when all three sets hit 5")
        XCTAssertEqual(p.days[0].exercises[1].scheme, "3x8–10")
        XCTAssertEqual(p.days[0].exercises[2].note, "")
        XCTAssertEqual(p.days[1].exercises.map(\.name), ["bench-press", "chin-ups"], "names fold to the log's kebab-case")
        XCTAssertEqual(p.days[1].exercises[1].scheme, "3xAMRAP")
    }

    func testABulletWithoutASchemeIsNotALift() {
        XCTAssertNil(Programme.parseExercise("a note that is not a lift"))
        XCTAssertNil(Programme.parseExercise("squat"))
        XCTAssertNil(Programme.parseExercise("squat x5"))
        XCTAssertNotNil(Programme.parseExercise("squat 5x3"))
    }

    func testEmptyAndProseOnlyFilesAreEmpty() {
        XCTAssertTrue(Programme.parse("").isEmpty)
        XCTAssertTrue(Programme.parse("# Title\n\nJust words.\n").isEmpty)
        XCTAssertTrue(Programme.parse("## Day\n\nno bullets").isEmpty, "a day with no lifts is dropped")
    }

    func testProgramBlockLiftsOutOfAReply() {
        let reply = CoachContext.parseReply("Here it is.\n\n```program.md\n# Plan\n\n## Day A\n- squat 3x5\n```")
        XCTAssertEqual(reply.program, "# Plan\n\n## Day A\n- squat 3x5")
        XCTAssertEqual(reply.prose, "Here it is.")
        XCTAssertFalse(reply.isWritingProgram)
        XCTAssertTrue(CoachContext.parseReply("```program.md\n# Pl").isWritingProgram)
    }

    func testProgrammeIsFedAndTheDesignBriefIsThere() {
        let excerpt = CoachContext.excerpt(from: [Session(date: Session.dateFormatter.date(from: "2026-08-01")!,
                                                         exercises: [ExerciseEntry(name: "squat", sets: [WorkSet(weight: 100, added: nil, reps: 5)])])])
        let text = CoachContext.systemPrompt(for: excerpt, brief: CoachContext.Brief(program: file))
        XCTAssertTrue(text.contains("<programme>"), text)
        XCTAssertTrue(text.contains("YOUR PROGRAMME."), text)
        XCTAssertTrue(text.contains("PROGRAMMES. When they ask for a programme"), text)
        XCTAssertTrue(text.contains("Adherence first"), text)
        XCTAssertFalse(CoachContext.systemPrompt(for: excerpt, mode: .goalsInterview).contains("PROGRAMMES. When"))
    }
}
