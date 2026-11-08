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

    // MARK: Surviving a kill

    /// What the Log tab saves on every change, written and read back as a
    /// relaunch would.
    private func relaunched(_ d: SessionDraft) throws -> SessionDraft {
        try JSONDecoder().decode(SessionDraft.self, from: JSONEncoder().encode(d))
    }

    func testHeldMeasurementComesBackAfterAKill() throws {
        let s1 = set(73.5), s2 = set(73.5)
        var held = measured(73.5)
        held.left = .reps(2)                       // answered in Grepp before the kill
        var riding = measured(73.5)
        riding.mcv = [0.45, 0.41]
        riding.left = .failed
        var d = draft([s1, s2], held: held)
        d.measurements = [s1.id: riding]
        d.attachOffer = s2.id
        d.repsNote = "BarVelo counted 3 · you had 8"
        d.setsWhenMeasureOpened = 1
        let back = try relaunched(d)
        XCTAssertEqual(back, d)
        XCTAssertEqual(back.measured?.left, .reps(2))
        XCTAssertEqual(back.measurements?[s1.id]?.left, .failed)
        XCTAssertEqual(back.attachOffer, s2.id)
        XCTAssertEqual(back.repsNote, "BarVelo counted 3 · you had 8")
        // Speeds held on their own are worth keeping.
        var bare = SessionDraft(date: day, name: "", sets: [], isBodyweight: false,
                                weightText: "", addedText: "", repsText: "", plan: nil, queue: [], restStart: nil)
        bare.measured = held
        XCTAssertFalse(bare.isEmpty)
    }

    func testAnOlderDraftHasNoOffer() throws {
        let legacy = """
        {"date":"2026-11-07","name":"bench","sets":[],"isBodyweight":false,
         "weightText":"","addedText":"","repsText":"","queue":[]}
        """
        let d = try JSONDecoder().decode(SessionDraft.self, from: Data(legacy.utf8))
        XCTAssertNil(d.attachOffer)
        XCTAssertNil(d.repsNote)
        XCTAssertNil(d.measured)
    }

    func testAttachAfterAKillLandsOnTheOfferedSet() throws {
        let s1 = set(73.5), s2 = set(73.5)
        var held = measured(73.5)
        held.left = .reps(1)
        var d = draft([s1, s2], held: held)
        d.attachOffer = s2.id
        d.repsNote = "BarVelo counted 3 · you had 8"
        var back = try relaunched(d)
        XCTAssertTrue(back.attachHeld(to: try XCTUnwrap(back.attachOffer)))
        XCTAssertNil(back.measured)
        XCTAssertNil(back.attachOffer)
        XCTAssertNil(back.repsNote)
        XCTAssertEqual(back.measurements?[s2.id]?.left, .reps(1), "the answer rides along")
        // Finish numbers it as set 2, the set it was offered to.
        let lines = VelocitySet.numbered(back.measurements!, committed: back.sets, dayLinesOfLift: [],
                                         occurrence: nil, lift: "bench", on: day)
        XCTAssertEqual(lines.map(\.setNumber), [2])
        // Once is all: nothing held, nothing to attach; a set with speeds keeps them.
        XCTAssertFalse(back.attachHeld(to: s1.id))
        var again = draft([s1], held: measured(73.5))
        again.measurements = [s1.id: riding()]
        XCTAssertFalse(again.attachHeld(to: s1.id))
        XCTAssertFalse(again.attachHeld(to: UUID()), "a set removed meanwhile")
        XCTAssertNotNil(again.measured)
    }
    private func riding() -> VelocitySet { var v = measured(73.5); v.mcv = [0.5]; return v }

    func testTheSameLinkAfterAKillIsOneSet() throws {
        let s1 = set(73.5)
        let v = measured(73.5)
        // Held, answered since, then killed: the link delivered again is the same set.
        var answered = v
        answered.left = .reps(2)
        let held = try relaunched(draft([s1], held: answered))
        XCTAssertTrue(held.holds(v))
        // Attached to a set: still the same set.
        var landed = draft([s1], held: nil)
        landed.measurements = [s1.id: answered]
        XCTAssertTrue(try relaunched(landed).holds(v))
        // Another set is not.
        var other = v
        other.mcv = [0.41]
        XCTAssertFalse(held.holds(other))
        XCTAssertFalse(draft([], held: nil).holds(v))
    }

    func testReceivedLinksAreRememberedAcrossALaunch() throws {
        var seen = ReceivedVelocity()
        let v = measured(73.5)
        XCTAssertTrue(seen.take(v))
        XCTAssertFalse(seen.take(v), "a double delivery")
        var back = try JSONDecoder().decode(ReceivedVelocity.self, from: JSONEncoder().encode(seen))
        XCTAssertFalse(back.take(v), "already written to velocity.md, say: not a new set")
        // The last twenty are kept.
        for i in 0..<ReceivedVelocity.limit {
            var w = v
            w.mcv = [0.5 + Double(i) / 100]
            XCTAssertTrue(back.take(w))
        }
        XCTAssertEqual(back.sets.count, ReceivedVelocity.limit)
        XCTAssertTrue(back.take(v), "forgotten after twenty more")
    }
}
