import XCTest
@testable import LiftLogCore

final class VelocityLandingTests: XCTestCase {

    private let day = Session.dateFormatter.date(from: "2026-11-07")!
    private func measured(_ load: Double?, added: Double? = nil, lift: String = "bench-press") -> VelocitySet {
        VelocitySet(date: day, lift: lift, load: load, added: added, mcv: [0.40, 0.35, 0.30])
    }
    private func set(_ kg: Double?, _ reps: Int = 8, added: Double? = nil) -> WorkSet {
        WorkSet(weight: kg, added: added, reps: reps)
    }

    func testLoadMatching() {
        XCTAssertTrue(measured(73.5).matchesLoad(of: set(73.5)))
        XCTAssertFalse(measured(73.5).matchesLoad(of: set(76)))
        XCTAssertFalse(measured(73.5).matchesLoad(of: set(nil)))
        XCTAssertTrue(measured(nil, added: 10).matchesLoad(of: set(nil, added: 10)))
        XCTAssertFalse(measured(nil, added: 10).matchesLoad(of: set(nil)))
        XCTAssertTrue(measured(nil).matchesLoad(of: set(nil)))
    }

    func testSameHandoffIgnoresTheAnswerGivenSince() {
        let v = measured(73.5)
        var answered = v
        answered.left = .reps(1)
        XCTAssertTrue(v.isSameHandoff(as: answered))
        var other = v
        other.mcv = [0.41]
        XCTAssertFalse(v.isSameHandoff(as: other))
    }

    func testAttachOfferedForTheSetLandedWhileMeasuring() {
        let s1 = set(73.5), s2 = set(73.5)
        let v = measured(73.5)
        // One set when BarVelo opened, two now: set 2 was landed meanwhile.
        XCTAssertEqual(v.attachCandidate(sets: [s1, s2], measurements: [:], setsWhenOpened: 1), 1)
        // Nothing landed since: the speeds are for the next set.
        XCTAssertNil(v.attachCandidate(sets: [s1, s2], measurements: [:], setsWhenOpened: 2))
        // Not opened from here: no guess.
        XCTAssertNil(v.attachCandidate(sets: [s1, s2], measurements: [:], setsWhenOpened: nil))
        // Already has speeds.
        XCTAssertNil(v.attachCandidate(sets: [s1, s2], measurements: [s2.id: v], setsWhenOpened: 1))
        // Another load.
        XCTAssertNil(v.attachCandidate(sets: [s1, set(76)], measurements: [:], setsWhenOpened: 1))
        XCTAssertNil(v.attachCandidate(sets: [], measurements: [:], setsWhenOpened: 0))
    }

    private func draft(_ sets: [WorkSet], held: VelocitySet?, name: String = "bench") -> SessionDraft {
        var d = SessionDraft(date: day, name: name, sets: sets, isBodyweight: false,
                             weightText: "", addedText: "", repsText: "", plan: nil, queue: [], restStart: nil)
        d.measured = held
        return d
    }

    func testLockScreenSetTakesTheHeldMeasurement() {
        let s1 = set(73.5)
        var d = draft([s1], held: measured(73.5))
        XCTAssertTrue(d.takeHeldMeasurement())
        XCTAssertNil(d.measured)
        XCTAssertEqual(d.measurements?[s1.id]?.mcv, [0.40, 0.35, 0.30])
        // Finish numbers it as set 1, the set it rode on.
        let lines = VelocitySet.numbered(d.measurements!, committed: d.sets, dayLinesOfLift: [], occurrence: nil,
                                         lift: "bench", on: day)
        XCTAssertEqual(lines.map(\.setNumber), [1])
    }

    func testLockScreenSetAtAnotherLoadLeavesItHeld() {
        var d = draft([set(76)], held: measured(73.5))
        XCTAssertFalse(d.takeHeldMeasurement())
        XCTAssertNotNil(d.measured)
        XCTAssertNil(d.measurements)
        // Another lift's measurement isn't taken either.
        var row = draft([set(73.5)], held: measured(73.5, lift: "seal-row"))
        XCTAssertFalse(row.takeHeldMeasurement())
        // A set that already has speeds keeps them.
        let s = set(73.5)
        var both = draft([s], held: measured(73.5))
        both.measurements = [s.id: measured(73.5)]
        XCTAssertFalse(both.takeHeldMeasurement())
        XCTAssertNotNil(both.measured)
    }

    func testDraftKeepsWhenMeasureWasOpened() throws {
        var d = draft([set(73.5)], held: nil)
        d.setsWhenMeasureOpened = 1
        let back = try JSONDecoder().decode(SessionDraft.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.setsWhenMeasureOpened, 1)
    }

    func testRepsLeftChoicesWriteTheLine() {
        var v = measured(73.5)
        v.setNumber = 3
        v.logged = set(73.5, 3)
        let choices = VelocitySet.RepsLeftChoice.allCases.filter { $0 != .none }
        XCTAssertEqual(choices.map(\.short), ["fail", "0", "1", "2", "3+"])
        var lines: [String] = []
        for c in choices {
            v.left = c.left
            lines.append(String(v.line.split(separator: " ").drop { $0 != "loss" }.dropFirst(2).joined(separator: " ")))
            // The line reads back as answered.
            XCTAssertEqual(VelocityRecord(line: v.line)?.left, c.left)
        }
        XCTAssertEqual(lines, ["fail", "left 0", "left 1", "left 2", "left 3"])
        // BarVelo's answer, whatever it was, lights its chip.
        XCTAssertEqual(VelocitySet.RepsLeftChoice(.reps(5)), .threePlus)
        XCTAssertEqual(VelocitySet.RepsLeftChoice(nil), .none)
        XCTAssertNil(VelocitySet.RepsLeftChoice.none.left)
    }
}
