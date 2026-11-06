import XCTest
@testable import LiftLogCore

final class VelocityLogTests: XCTestCase {

    private let squat1006 = "2026-10-06 squat set 3 110x12 mcv 0.39 0.41 0.42 0.41 0.37 0.36 0.37 0.35 0.35 0.33 0.35 0.32 loss 24%"
    private let squat0927 = "2026-09-27 squat set 1 105x8 mcv 0.55 0.55 0.54 0.56 0.53 0.50 0.53 0.51 loss 9%"
    private let ohp1006 = "2026-10-06 over-head-press set 3 42.5x9 mcv 0.49 0.47 0.44 0.46 0.41 0.41 0.36 0.33 0.26 loss 47% fail"

    private func day(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }
    private func record(_ line: String) throws -> VelocityRecord { try XCTUnwrap(VelocityRecord(line: line)) }
    private func short(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }

    func testReadsRealSquatLine() throws {
        let r = try record(squat1006)
        XCTAssertEqual(r.date, day("2026-10-06"))
        XCTAssertEqual(r.lift, "squat")
        XCTAssertEqual(r.setNumber, 3)
        XCTAssertEqual(r.load, 110)
        XCTAssertNil(r.added)
        XCTAssertEqual(r.reps, 12)
        XCTAssertEqual(r.mcv.count, 12)
        XCTAssertEqual(r.loss!, 0.24, accuracy: 1e-9)
        XCTAssertEqual(r.best, 0.42)
        XCTAssertEqual(r.lastRep, 0.32)
        XCTAssertNil(r.rirEstimate)
        XCTAssertNil(r.left)
        XCTAssertNil(r.rpe)
        XCTAssertNil(r.v1rm)
        XCTAssertEqual(r.detail, "set 3 · 110×12 · 0.42 → 0.32 m/s · −24%")
    }

    func testReadsEarlierSquatAndFailedPress() throws {
        let s = try record(squat0927)
        XCTAssertEqual(s.setNumber, 1)
        XCTAssertEqual(s.load, 105)
        XCTAssertEqual(s.best, 0.56)
        XCTAssertEqual(s.lastRep, 0.51)
        XCTAssertEqual(s.loss!, 0.09, accuracy: 1e-9)

        let p = try record(ohp1006)
        XCTAssertEqual(p.lift, "over-head-press")
        XCTAssertEqual(p.load, 42.5)
        XCTAssertEqual(p.reps, 9)
        XCTAssertEqual(p.left, .failed)
        XCTAssertEqual(p.rpe, 10)
        XCTAssertFalse(p.rpeIsEstimated)
        XCTAssertEqual(p.effort, "fail")
        XCTAssertEqual(p.detail, "set 3 · 42.5×9 · 0.49 → 0.26 m/s · −47% · fail")
    }

    func testOptionalEffortTokens() throws {
        let est = try record("2026-11-06 over-head-press set 2 42.5x9 mcv 0.78 0.41 loss 47% rir ~1.5 v1rm 47.5")
        XCTAssertEqual(est.rirEstimate, 1.5)
        XCTAssertEqual(est.rpe, 8.5)
        XCTAssertTrue(est.rpeIsEstimated)
        XCTAssertEqual(est.effort, "est. RPE 8.5")
        XCTAssertEqual(est.v1rm, 47.5)

        let told = try record("2026-11-06 squat set 1 100x5 mcv 0.52 0.41 loss 21% rir ~0 left 1")
        XCTAssertEqual(told.left, .reps(1))
        XCTAssertEqual(told.rpe, 9)
        XCTAssertEqual(told.effort, "RPE 9")
        XCTAssertTrue(told.detail.hasSuffix("· RPE 9"))
    }

    func testRPEMatchesVelocitySet() throws {
        for (left, rir) in [(VelocitySet.Left?.none, 2.3), (.reps(7), 0), (.failed, 3), (nil, 12)] {
            var v = VelocitySet(date: Date(), lift: "squat", load: 100, mcv: [0.5])
            v.left = left; v.rirEstimate = rir
            XCTAssertEqual(VelocitySet.rpe(left: left, rirEstimate: rir), v.rpe)
        }
    }

    func testBodyweightOlderAndComputedLoss() throws {
        let bw = try record("2026-08-01 chin-ups bwx6 mcv 0.60 0.50")
        XCTAssertNil(bw.setNumber)
        XCTAssertNil(bw.load)
        XCTAssertNil(bw.added)
        XCTAssertEqual(bw.loss!, 1.0 / 6, accuracy: 1e-9)   // no loss token: computed
        XCTAssertEqual(bw.loadLabel, "bodyweight")

        let added = try record("2026-08-02 chin-ups set 2 bw+10x5 mcv 0.4 0.3 loss 25%")
        XCTAssertNil(added.load)
        XCTAssertEqual(added.added, 10)
        XCTAssertEqual(added.loadLabel, "bw +10 kg")
        XCTAssertFalse(added.sameLoad(as: bw))
        XCTAssertTrue(bw.sameLoad(as: try record("2026-08-09 chin-ups bwx6 mcv 0.6")))
    }

    func testSkipsHeaderProseAndMalformedLines() {
        let file = """
        # Bar velocity

        One line per set, measured by BarVelo: the day, the lift, …
        \(squat0927)
        2026-10-01 squat 100x5 loss 20%
        2026-10-02 squat 100x5 mcv
        2026-10-03 squat 100x5 mcv 0.5 abc
        2026-10-04 mcv 0.5 0.4
        2026-13-45 squat 100x5 mcv 0.5
        2026-10-05 squat set 2 100x5 mcv 0.5 -0.1
        2026-10-06 squat set 2 100x5 mcv 0.5 0.4 loss lots future-token 7
        \(squat1006)
        \(ohp1006)
        """
        let all = VelocityRecord.parse(file)
        XCTAssertEqual(all.count, 5)
        // `abc` ends the speeds and is dropped as an unknown extra.
        XCTAssertEqual(all[1].mcv, [0.5])
        // A loss that doesn't read is computed instead.
        XCTAssertEqual(all[2].loss!, 0.2, accuracy: 1e-9)
    }

    func testRecordsForLiftSortedAndMatched() throws {
        let file = [ohp1006, squat1006, "2026-10-06 squat set 1 100x5 mcv 0.6", squat0927,
                    "2026-10-08 overhead press 40x5 mcv 0.5"].joined(separator: "\n")
        let all = VelocityRecord.parse(file)
        let squats = VelocityRecord.records(for: "Squat", in: all)
        XCTAssertEqual(squats.map(\.setNumber), [1, 1, 3])
        XCTAssertEqual(squats.map(\.date), [day("2026-09-27"), day("2026-10-06"), day("2026-10-06")])
        let press = VelocityRecord.records(for: "over-head-press", in: all)
        XCTAssertEqual(press.count, 2)
        XCTAssertEqual(press.last?.lift, "overhead press")
        XCTAssertTrue(VelocityRecord.records(for: "deadlift", in: all).isEmpty)
    }

    func testSameLoadComparison() throws {
        let earlier = "2026-09-29 squat set 2 110x10 mcv 0.39 0.38 0.36 loss 8%"
        let all = VelocityRecord.parse([squat0927, earlier, squat1006].joined(separator: "\n"))
        let c = try XCTUnwrap(VelocityRecord.sameLoadComparison(VelocityRecord.records(for: "squat", in: all)))
        XCTAssertEqual(c.earlier.date, day("2026-09-29"))
        XCTAssertEqual(c.delta, 0.03, accuracy: 1e-9)
        XCTAssertEqual(c.percent, 0.03 / 0.39 * 100, accuracy: 1e-6)
        XCTAssertTrue(c.isFaster)
        XCTAssertEqual(c.sentence(day: short), "at 110 kg: 0.03 m/s faster than 29 Sep")
    }

    func testSameLoadSlowerSameAndNone() throws {
        func compare(_ lines: [String]) -> VelocityRecord.Comparison? {
            VelocityRecord.sameLoadComparison(VelocityRecord.records(for: "squat", in: VelocityRecord.parse(lines.joined(separator: "\n"))))
        }
        // Different loads only: nothing to compare.
        XCTAssertNil(compare([squat0927, squat1006]))
        // Same day only: not an earlier set.
        XCTAssertNil(compare(["2026-10-06 squat set 1 110x5 mcv 0.5", squat1006]))

        let slower = try XCTUnwrap(compare(["2026-09-20 squat 110.004x5 mcv 0.47", squat1006]))
        XCTAssertEqual(slower.delta, -0.05, accuracy: 1e-9)
        XCTAssertFalse(slower.isFaster)
        XCTAssertEqual(slower.sentence(day: short), "at 110 kg: 0.05 m/s slower than 20 Sep")

        let same = try XCTUnwrap(compare(["2026-09-20 squat 110x5 mcv 0.41", squat1006]))
        XCTAssertTrue(same.isSame)
        XCTAssertEqual(same.sentence(day: short), "at 110 kg: same velocity as 20 Sep")

        // The most recent earlier one at the load, not the first.
        let recent = try XCTUnwrap(compare(["2026-09-01 squat 110x5 mcv 0.30", "2026-09-20 squat 110x5 mcv 0.40", squat1006]))
        XCTAssertEqual(recent.earlier.date, day("2026-09-20"))
    }

    func testLatestV1RM() throws {
        let all = VelocityRecord.parse("""
        2026-09-01 squat 100x5 mcv 0.5 v1rm 130
        2026-09-08 squat 100x5 mcv 0.5 v1rm 132.5
        2026-09-15 squat 100x5 mcv 0.5
        """)
        let latest = try XCTUnwrap(VelocityRecord.latestV1RM(VelocityRecord.records(for: "squat", in: all)))
        XCTAssertEqual(latest.v1rm, 132.5)
        XCTAssertEqual(latest.date, day("2026-09-08"))
        XCTAssertNil(VelocityRecord.latestV1RM(VelocityRecord.parse(squat1006)))
    }
}
