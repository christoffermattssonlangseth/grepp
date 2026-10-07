import XCTest
@testable import LiftLogCore

final class IntakeTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = Session.dateFormatter.timeZone
        return c
    }
    private func day(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }

    func testTheCoachingSectionStatesTheFacts() {
        var intake = Intake()
        intake.goal = .muscle
        intake.goalWords = "squat my bodyweight"
        intake.days = 3
        intake.minutes = 45
        intake.place = .home
        intake.equipment = [.barbell, .bench, .pullUpBar]
        intake.limits = "left shoulder, no overhead pressing"
        let section = intake.coachingSection()
        XCTAssertTrue(section.hasPrefix("## About me\n"))
        XCTAssertTrue(section.contains("- Experience: new to lifting"))
        XCTAssertTrue(section.contains("- Goal: build muscle — squat my bodyweight"))
        XCTAssertTrue(section.contains("- Trains 3 days a week, about 45 minutes a session"))
        XCTAssertTrue(section.contains("- Equipment: barbell and rack, bench, pull-up bar"))
        XCTAssertTrue(section.contains("- Work around: left shoulder, no overhead pressing"))
    }

    func testTheSectionGoesFirstOrReplacesItselfAndKeepsTheRest() {
        let first = Intake().coachingSection()
        XCTAssertEqual(Intake.merging(first, into: ""), first)

        let notes = "# How I train\n\nMornings only.\n"
        let merged = Intake.merging(first, into: notes)
        XCTAssertTrue(merged.hasPrefix("## About me\n"))
        XCTAssertTrue(merged.hasSuffix(notes))

        var again = Intake()
        again.days = 4
        let replaced = Intake.merging(again.coachingSection(), into: merged)
        XCTAssertTrue(replaced.contains("Trains 4 days a week"))
        XCTAssertFalse(replaced.contains("Trains 3 days a week"))
        XCTAssertTrue(replaced.hasSuffix(notes), "the lifter's own notes are untouched")
        XCTAssertEqual(replaced.components(separatedBy: "## About me").count, 2, "one section, not two")
    }

    func testTheGoalLineIsOneTheTargetCardReads() {
        var intake = Intake()
        XCTAssertNil(intake.goalsLine(calendar: utc), "no words, no line")
        intake.goalWords = "squat 100 kg"
        intake.goalBy = day("2027-06-30")
        let line = intake.goalsLine(calendar: utc)!
        XCTAssertEqual(line, "- squat 100 kg by 30 Jun 2027")
        let goals = Intake.adding(line, to: "")
        XCTAssertEqual(goals, "# Goals\n\n- squat 100 kg by 30 Jun 2027\n")
        XCTAssertEqual(Intake.adding(line, to: goals), goals, "not added twice")
        let target = Targets.parse(goals, lifts: ["squat"], today: day("2026-10-05"), calendar: utc).first
        XCTAssertEqual(target?.value, 100)
        XCTAssertEqual(target?.by, day("2027-06-30"))
    }

    func testTheStarterFitsTheEquipmentAndReadsAsAProgramme() {
        var barbell = Intake()
        barbell.equipment = [.barbell, .bench, .pullUpBar]
        let p = Programme.parse(barbell.starter())
        XCTAssertEqual(p.title, "Beginner, full body")
        XCTAssertEqual(p.days.map(\.title), ["Day A", "Day B"])
        XCTAssertEqual(p.days[0].exercises.map(\.name), ["squat", "bench-press", "barbell-row"])
        XCTAssertEqual(p.days[1].exercises.map(\.name), ["squat", "over-head-press", "deadlift", "chin-ups"])
        XCTAssertEqual(p.days[1].exercises[2].scheme, "1x5")

        var dumbbells = Intake()
        dumbbells.place = .home
        dumbbells.equipment = [.dumbbells]
        let d = Programme.parse(dumbbells.starter())
        XCTAssertEqual(d.days[0].exercises.map(\.name), ["bulgarian-split-squat", "push-ups", "dumbbell-row"])
        XCTAssertEqual(d.days[1].exercises.map(\.name), ["romanian-deadlift", "dumbbell-shoulder-press", "dumbbell-row"])

        var nothing = Intake()
        nothing.place = .bodyweight
        nothing.equipment = []
        let n = Programme.parse(nothing.starter())
        XCTAssertEqual(n.days.flatMap(\.exercises).count, 6)
        XCTAssertTrue(n.days.flatMap(\.exercises).allSatisfy { MuscleMap().share(for: $0.name) != nil },
                      "every lift is one the muscle map counts")
    }

    func testTheCoachIsToldTheRackAndToUseTheSetup() {
        let rack = PlateInventory(counts: [20: 4, 10: 2, 2.5: 2])
        let line = CoachContext.gymLine(bar: 15, inventory: rack)
        XCTAssertTrue(line.contains("A 15 kg bar"))
        XCTAssertTrue(line.contains("20×4, 10×2, 2.5×2"))
        let prompt = CoachContext.systemPrompt(for: CoachContext.excerpt(from: []), gym: line)
        XCTAssertTrue(prompt.contains("THEIR RACK"))
        XCTAssertTrue(prompt.contains("\"About me\" section"), "the empty log points at the setup")
        XCTAssertTrue(prompt.contains("never a lift they have no kit for"))
        XCTAssertFalse(CoachContext.systemPrompt(for: CoachContext.excerpt(from: [])).contains("THEIR RACK"))
    }
}
