import XCTest
@testable import LiftLogCore

final class ProgrammeTextTests: XCTestCase {

    private let file = """
    # Upper / Lower

    Some prose the coach wrote about the plan.

    ## Day A — Lower
    - squat 3x5 — add 2.5 kg when all three sets hit 5
    A cue between two lifts.
    - romanian-deadlift 3x8–10

    ## Day B — Upper
    - bench-press rpt 3x6-8
    - chin-ups 3xAMRAP
    """

    func testTheParserRemembersWhereEveryLineLives() {
        let p = Programme.parse(file)
        XCTAssertEqual(p.days[0].line, 4)
        XCTAssertEqual(p.days[0].exercises.map(\.line), [5, 7])
        XCTAssertEqual(p.days[0].end, 9)
        XCTAssertEqual(p.days[1].line, 9)
        XCTAssertEqual(p.days[1].end, 12)
    }

    func testTheLineWrittenIsTheLineRead() {
        let ex = Programme.Exercise(name: "over-head-press", scheme: "3x6-8", note: "add 2.5 kg once 3x8", rpt: true)
        let line = ProgrammeText.line(for: ex)
        XCTAssertEqual(line, "- over-head-press rpt 3x6-8 — add 2.5 kg once 3x8")
        let back = Programme.parse("## Day\n" + line).days[0].exercises[0]
        XCTAssertEqual(back, ex)
    }

    func testEditsTouchOnlyTheirLines() {
        let p = Programme.parse(file)
        let lines = file.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let changed = ProgrammeText.replacing(line: p.days[0].exercises[0].line,
                                              with: ProgrammeText.line(for: Programme.Exercise(name: "squat", scheme: "5x5", note: "", rpt: false)),
                                              in: file)
        var expected = lines; expected[5] = "- squat 5x5"
        XCTAssertEqual(changed, expected.joined(separator: "\n"))

        let added = ProgrammeText.adding(Programme.Exercise(name: "calf-raise", scheme: "3x12", note: "", rpt: false), to: p.days[0], in: file)
        var withAdd = lines; withAdd.insert("- calf-raise 3x12", at: 8)
        XCTAssertEqual(added, withAdd.joined(separator: "\n"))
        XCTAssertEqual(Programme.parse(added).days[0].exercises.map(\.name), ["squat", "romanian-deadlift", "calf-raise"])

        let removed = ProgrammeText.removing(line: p.days[1].exercises[1].line, in: file)
        XCTAssertEqual(Programme.parse(removed).days[1].exercises.map(\.name), ["bench-press"])
        XCTAssertTrue(removed.contains("Some prose the coach wrote"))
    }

    func testReorderKeepsTheCueBetweenTheLifts() {
        let p = Programme.parse(file)
        let day = p.days[0]
        let swapped = ProgrammeText.reordering(day, to: [day.exercises[1], day.exercises[0]], in: file)
        let lines = swapped.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines[5], "- romanian-deadlift 3x8–10")
        XCTAssertEqual(lines[6], "A cue between two lifts.")
        XCTAssertEqual(lines[7], "- squat 3x5 — add 2.5 kg when all three sets hit 5")
    }

    func testDaysAreAddedRenamedAndRemovedAroundTheProse() {
        let p = Programme.parse(file)
        let renamed = ProgrammeText.renaming(p.days[1], to: "Day B — Push", in: file)
        XCTAssertTrue(renamed.contains("## Day B — Push"))
        XCTAssertEqual(Programme.parse(renamed).days.map(\.title), ["Day A — Lower", "Day B — Push"])

        let more = ProgrammeText.appendingDay("Day C — Legs", exercises: [Programme.Exercise(name: "leg-press", scheme: "3x10", note: "", rpt: false)], to: file)
        XCTAssertTrue(more.hasSuffix("\n## Day C — Legs\n- leg-press 3x10\n"))
        XCTAssertEqual(Programme.parse(more).days.count, 3)

        let fewer = ProgrammeText.removing(p.days[0], from: file)
        let q = Programme.parse(fewer)
        XCTAssertEqual(q.days.map(\.title), ["Day B — Upper"])
        XCTAssertTrue(fewer.contains("Some prose the coach wrote"))
        XCTAssertFalse(fewer.contains("A cue between two lifts."))
        XCTAssertEqual(q.title, "Upper / Lower")

        let bold = "**Day A**\n- squat 3x5\n"
        XCTAssertEqual(ProgrammeText.renaming(Programme.parse(bold).days[0], to: "Day One", in: bold), "**Day One**\n- squat 3x5\n")
    }

    func testIdsStayApartWhenTitlesAndLiftsRepeat() {
        let p = Programme.parse("""
        ## Upper
        - bench-press 3x5
        - bench-press 3x5 — back-off

        ## Upper
        - row 3x8
        """)
        XCTAssertEqual(p.days.map(\.title), ["Upper", "Upper"])
        XCTAssertNotEqual(p.days[0].id, p.days[1].id)
        XCTAssertNotEqual(p.days[0].exercises[0].id, p.days[0].exercises[1].id)
    }

    func testADayWithItsLastLiftRemovedCanStillBeRemoved() {
        let md = "# Plan\n\n## Day A\n- squat 3x5\n\n## Day B\n- bench 3x5\n"
        let p = Programme.parse(md)
        let bare = ProgrammeText.removing(line: p.days[0].exercises[0].line, in: md)
        let left = Programme.parse(bare)
        XCTAssertEqual(left.days.map(\.title), ["Day B"])
        XCTAssertEqual(left.emptyDays.map(\.title), ["Day A"], "the bare heading is still on screen")
        XCTAssertEqual(ProgrammeText.removing(left.emptyDays[0], from: bare), "# Plan\n\n## Day B\n- bench 3x5\n")
        // And it can be filled again, under its heading.
        let refilled = ProgrammeText.adding(Programme.Exercise(name: "deadlift", scheme: "1x5", note: "", rpt: false),
                                            to: left.emptyDays[0], in: bare)
        XCTAssertEqual(Programme.parse(refilled).days.map(\.title), ["Day A", "Day B"])
    }

    func testOnlyBareHeadingsAreEmptyDays() {
        let p = Programme.parse("""
        # Plan

        ## Week 1
        ### Day A
        - squat 3x5

        ## Notes
        Deload every fourth week.
        """)
        XCTAssertEqual(p.days.map(\.title), ["Day A"])
        XCTAssertTrue(p.emptyDays.isEmpty, "a group heading and a prose section are not days")
    }

    func testALiftMayStartWithANumber() {
        let a = Programme.parseExercise("45-degree back extension 3x10")
        XCTAssertEqual(a?.name, "45-degree-back-extension")
        XCTAssertEqual(a?.scheme, "3x10")
        XCTAssertEqual(Programme.parseExercise("1-arm row 3x8")?.name, "1-arm-row")
        XCTAssertNil(Programme.parseExercise("4 weeks: squat 3x5"), "a sentence with a number first is still prose")
    }

    func testTheHeadinglessDayCanBeRenamedAndRemoved() {
        let md = "# Plan\n\n- squat 3x5\n- bench 3x5\n\n## Day B\n- row 3x8\n"
        let p = Programme.parse(md)
        XCTAssertEqual(p.days[0].title, "Session")
        let renamed = ProgrammeText.renaming(p.days[0], to: "Day A", in: md)
        XCTAssertEqual(renamed, "# Plan\n\n## Day A\n- squat 3x5\n- bench 3x5\n\n## Day B\n- row 3x8\n")
        XCTAssertEqual(Programme.parse(renamed).days.map(\.title), ["Day A", "Day B"])
        let removed = ProgrammeText.removing(p.days[0], from: md)
        XCTAssertEqual(removed, "# Plan\n\n## Day B\n- row 3x8\n")
    }
}
