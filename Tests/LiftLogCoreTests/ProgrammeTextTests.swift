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
}
