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

    func testFitsRealOverheadPress() throws {
        let m = try XCTUnwrap(ReserveModel.fit(records(ohp1006)))
        XCTAssertEqual(m.a, -7.057, accuracy: 0.01)
        XCTAssertEqual(m.b, 25.714, accuracy: 0.01)
        XCTAssertEqual(m.failureSpeed, 0.27, accuracy: 0.01)
        XCTAssertEqual(m.speedPerRep, 0.039, accuracy: 0.001)
        XCTAssertEqual(m.points, 6)
        XCTAssertEqual(m.labelledSets, 1)
        XCTAssertLessThan(m.looError, 1)
        XCTAssertEqual(m.looError, 0.6, accuracy: 0.05)
        XCTAssertEqual(m.reserve(at: 0.40), 3.23, accuracy: 0.05)
        XCTAssertEqual(m.reserve(at: 0.10), 0)
        XCTAssertEqual(m.lookup.map(\.speed), [0.30, 0.40, 0.45])
        XCTAssertEqual(m.lookup.map(\.reserve)[0...1], [1, 3])
        XCTAssertEqual(m.summary(lift: "Overhead press"),
                       "Overhead press: failure ≈ 0.27 m/s, about 0.04 m/s per rep in reserve (1 labelled set, ±0.6 reps). Filmed the same way, 0.40 m/s ≈ 3 left.")
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
        let file = "# Bar speed\n\n" + ohp1006 + "\n2026-10-06 squat set 1 100x3 mcv 0.40 0.35 0.30\n"
        let brief = CoachContext.barSpeedBrief(file)
        XCTAssertTrue(brief.contains(ohp1006), brief)
        XCTAssertTrue(brief.contains("- over-head-press: failure ≈ 0.27 m/s, 0.039 m/s per rep in reserve, 1 labelled set, ±0.6 reps"), brief)
        XCTAssertFalse(brief.contains("- squat:"), brief)
        XCTAssertEqual(CoachContext.reserveBrief("2026-10-06 squat set 1 100x3 mcv 0.40 0.35 0.30\n"), "")
    }
}
