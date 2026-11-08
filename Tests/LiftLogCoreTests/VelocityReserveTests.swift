import XCTest
@testable import LiftLogCore

final class VelocityReserveTests: XCTestCase {

    private let ohp1006 = "2026-10-06 over-head-press set 3 42.5x9 mcv 0.49 0.47 0.44 0.46 0.41 0.41 0.36 0.33 0.26 loss 47% fail"

    private func records(_ lines: String...) -> [VelocityRecord] {
        VelocityRecord.parse(lines.joined(separator: "\n"))
    }

    func testFailLabelsEveryRep() throws {
        let r = try XCTUnwrap(VelocityRecord(line: ohp1006))
        XCTAssertEqual(r.ownReserve, 0)
        let p = r.reservePoints
        XCTAssertEqual(p.count, 9)
        XCTAssertEqual(p.first, .init(mcv: 0.49, reserve: 8))
        XCTAssertEqual(p.last, .init(mcv: 0.26, reserve: 0))
    }

    func testLeftNLabelling() throws {
        let r = try XCTUnwrap(VelocityRecord(line: "2026-10-08 squat set 1 100x3 mcv 0.50 0.45 0.40 left 2"))
        XCTAssertEqual(r.ownReserve, 2)
        XCTAssertEqual(r.reservePoints.map(\.reserve), [4, 3, 2])
        XCTAssertNil(try XCTUnwrap(VelocityRecord(line: "2026-10-08 squat 100x3 mcv 0.5 0.4")).ownReserve)
    }

    private let ohp1013 = "2026-10-13 over-head-press set 2 40x6 mcv 0.52 0.49 0.46 0.42 0.38 0.34 left 2"

    func testLineThroughRealOverheadPress() throws {
        // The line itself, ungated: one set gives numbers, but no model.
        let m = try XCTUnwrap(ReserveModel.candidate(records(ohp1006)))
        XCTAssertEqual(m.a, -7.057, accuracy: 0.01)
        XCTAssertEqual(m.b, 25.714, accuracy: 0.01)
        XCTAssertEqual(m.speedPerRep, 0.039, accuracy: 0.001)
        XCTAssertEqual(m.points, 6)
        XCTAssertEqual(m.labelledSets, 1)
        XCTAssertEqual(m.looError, 0.6, accuracy: 0.05)
        XCTAssertEqual(m.reserve(at: 0.40), 3.23, accuracy: 0.05)
        XCTAssertEqual(m.reserve(at: 0.10), 0)
        XCTAssertEqual(m.lookup.map(\.speed), [0.30, 0.40, 0.45])
        XCTAssertEqual(m.lookup.map(\.reserve)[0...1], [1, 3])
    }

    func testOneAnsweredSetIsNoModel() {
        // BarVelo's rule too: after one fail, the next set read ≈0 left.
        XCTAssertNil(ReserveModel.fit(records(ohp1006)))
        XCTAssertEqual(ReserveModel.assess(records(ohp1006)),
                       .notYet("One answered set so far: reading reps left from velocity takes two."))
        XCTAssertEqual(ReserveModel.assess(records("2026-10-06 squat set 1 100x5 mcv 0.40 0.38 0.35 0.33 0.30")),
                       .notYet("No answered sets yet: reading reps left from velocity takes two."))
        // No model: no estimate for an unanswered set either.
        let all = records(ohp1006, "2026-10-13 over-head-press set 1 40x5 mcv 0.52 0.50 0.48 0.45 0.40")
        XCTAssertEqual(VelocityRecord.proximity(all, model: ReserveModel.fit(all)).map(\.isOwn), [true])
    }

    func testTwoAgreeingSetsMakeAModel() throws {
        let m = try XCTUnwrap(ReserveModel.fit(records(ohp1006, ohp1013)))
        XCTAssertEqual(m.labelledSets, 2)
        XCTAssertLessThanOrEqual(m.looError, ReserveModel.maxLooError)
        let s = m.summary(lift: "Overhead press")
        XCTAssertTrue(s.hasPrefix("Overhead press: about \(m.speedPerRepLabel) m/s per rep in reserve (2 labelled sets, ±"), s)
        XCTAssertFalse(s.contains("failure"), s)
        XCTAssertEqual(m.speedPerRepLabel.split(separator: ".").last?.count, 3)
    }

    func testDisagreeingSetsAreRefused() throws {
        // The owner's seal rows: flat speed over the set, so speed says little
        // about reps left. Two answered sets that put the same speeds at very
        // different reserves don't make a model.
        let rows = records(
            "2026-11-07 seal-row set 3 62.5x14 mcv 0.77 0.73 0.70 0.75 0.71 0.70 0.73 0.65 0.65 0.66 0.73 0.65 0.66 0.63 loss 19% left 0",
            "2026-11-10 seal-row set 1 62.5x6 mcv 0.70 0.72 0.69 0.71 0.68 0.70 left 3")
        let c = try XCTUnwrap(ReserveModel.candidate(rows))
        XCTAssertGreaterThan(c.looError, ReserveModel.maxLooError)
        XCTAssertNil(ReserveModel.fit(rows))
        guard case .notYet(let why) = ReserveModel.assess(rows) else { return XCTFail() }
        XCTAssertTrue(why.hasPrefix("The answered sets don't agree on a line yet (±"), why)
    }

    func testFailureVelocityNeedsTwoSets() {
        let now = Session.dateFormatter.date(from: "2026-11-10")!
        let one = records(ohp1006)
        XCTAssertNil(VelocityRecord.failureVelocity(one, now: now))
        let two = records(ohp1006, "2026-10-20 over-head-press set 3 40x8 mcv 0.50 0.45 0.40 0.36 0.33 0.30 0.28 0.22 left 0")
        let fv = VelocityRecord.failureVelocity(two, now: now)
        XCTAssertEqual(fv?.sets, 2)
        XCTAssertEqual(fv?.speed ?? 0, 0.24, accuracy: 1e-9)
        // Older than twelve weeks: out, like the profile.
        let later = Session.dateFormatter.date(from: "2027-01-10")!
        XCTAssertNil(VelocityRecord.failureVelocity(two, now: later))
        XCTAssertEqual(VelocityRecord.failureSpeeds(two, now: later).count, 1)
    }

    func testInvalidWithTooFewPointsOrBackwards() {
        // Three reps: too few.
        XCTAssertNil(ReserveModel.fit(records("2026-10-06 squat set 1 100x3 mcv 0.40 0.35 0.30 fail")))
        // Unlabelled sets give nothing.
        XCTAssertNil(ReserveModel.fit(records("2026-10-06 squat set 1 100x5 mcv 0.40 0.38 0.35 0.33 0.30")))
        // Faster when closer to failure: not a model.
        XCTAssertNil(ReserveModel.fit(records("2026-10-06 squat set 1 100x5 mcv 0.30 0.32 0.35 0.38 0.40 fail")))
        // Far from failure: no rep within five of it.
        XCTAssertNil(ReserveModel.fit(records("2026-10-06 squat set 1 100x5 mcv 0.60 0.58 0.55 0.53 0.50 left 6")))
    }

    func testProximityLabelledAndEstimated() throws {
        let all = records(
            ohp1006,
            "2026-10-13 over-head-press set 1 40x5 mcv 0.52 0.50 0.48 0.45 0.40",
            "2026-10-13 over-head-press set 2 40x5 mcv 0.50 0.47 0.44 0.40 0.36 left 2",
            "2026-10-13 squat set 1 100x5 mcv 0.50 0.45 0.40 0.35 0.30")
        let press = VelocityRecord.records(for: "over-head-press", in: all)
        let m = try XCTUnwrap(ReserveModel.fit(press))
        XCTAssertEqual(m.labelledSets, 2)
        let p = VelocityRecord.proximity(press, model: m)
        XCTAssertEqual(p.map(\.isOwn), [true, false, true])
        XCTAssertEqual(p[0].reserve, 0)
        XCTAssertEqual(p[2].reserve, 2)
        XCTAssertEqual(p[1].reserve, m.reserve(at: 0.40), accuracy: 1e-9)
        // Without a model only the lifter's own answers remain.
        XCTAssertEqual(VelocityRecord.proximity(press, model: nil).map(\.isOwn), [true, true])

        XCTAssertEqual(VelocityRecord.failureSpeeds(press).map(\.speed), [0.26])
        XCTAssertEqual(VelocityRecord.labelledDays(press), 2)
    }

    func testCoachLine() {
        let now = Session.dateFormatter.date(from: "2026-10-20")!
        // One answered set: nothing for the coach.
        XCTAssertEqual(CoachContext.reserveBrief(ohp1006 + "\n", now: now), "")
        let file = "# Bar velocity\n\n" + ohp1006 + "\n" + ohp1013 + "\n2026-10-06 squat set 1 100x3 mcv 0.40 0.35 0.30\n"
        let brief = CoachContext.barVelocityBrief(file)
        XCTAssertTrue(brief.contains(ohp1006), brief)
        let m = ReserveModel.fit(records(ohp1006, ohp1013))!
        XCTAssertTrue(brief.contains("- over-head-press: \(m.speedPerRepLabel) m/s per rep in reserve, 2 labelled sets, ±"), brief)
        XCTAssertFalse(brief.contains("failure ≈"), brief)
        XCTAssertFalse(brief.contains("- squat:"), brief)
        XCTAssertEqual(CoachContext.reserveBrief("2026-10-06 squat set 1 100x3 mcv 0.40 0.35 0.30\n"), "")
        // Two sets at failure: the failure velocity, measured.
        let fails = ohp1006 + "\n2026-10-20 over-head-press set 3 40x8 mcv 0.50 0.45 0.40 0.36 0.33 0.30 0.28 0.22 left 0\n"
        XCTAssertTrue(CoachContext.reserveBrief(fails, now: now)
            .contains("- over-head-press: 0.24 m/s (median last rep of 2 sets ended with nothing left, last 12 weeks)"))
    }
}
