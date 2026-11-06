import XCTest
@testable import LiftLogCore

final class LoadVelocityTests: XCTestCase {
    private func records(_ text: String) -> [VelocityRecord] {
        VelocityRecord.parse(text)
    }
    /// Tests are dated in autumn 2026: judged from that day, not the machine's clock.
    private let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!
    private func fit(_ text: String, lift: String = "squat") -> LoadVelocityProfile.Fit {
        LoadVelocityProfile.fit(records(text), lift: lift, now: now)
    }
    private func profile(_ text: String, lift: String = "squat") throws -> LoadVelocityProfile {
        guard case .profile(let p) = fit(text, lift: lift) else {
            XCTFail("no profile"); throw XCTSkip()
        }
        return p
    }

    /// v = 1.5 − 0.01 · kg, fastest reps: 80 kg 0.70, 90 kg 0.60, 100 kg 0.50, 110 kg 0.40.
    private let clean = """
    2026-10-01 squat set 1 80x5 mcv 0.70 0.68 0.66 loss 6%
    2026-10-08 squat set 1 90x5 mcv 0.60 0.58 0.55 loss 8%
    2026-10-15 squat set 1 100x5 mcv 0.50 0.48 0.45 loss 10%
    2026-10-22 squat set 1 110x5 mcv 0.40 0.38 0.35 loss 13%
    """

    func testACleanProfileAndItsOneRepMax() throws {
        let p = try profile(clean)
        XCTAssertEqual(p.slope, -0.01, accuracy: 1e-9)
        XCTAssertEqual(p.intercept, 1.5, accuracy: 1e-9)
        XCTAssertEqual(p.rSquared, 1, accuracy: 1e-9)
        XCTAssertEqual(p.threshold, 0.30)                 // typical for a squat
        XCTAssertFalse(p.thresholdIsOwn)
        XCTAssertEqual(try XCTUnwrap(p.oneRepMax), 120, accuracy: 1e-6)
        XCTAssertEqual(p.load(at: 0.50), 100, accuracy: 1e-9)
    }

    func testOwnThresholdFromASetTakenToFailure() throws {
        let p = try profile(clean + "\n2026-10-29 squat set 1 105x6 mcv 0.45 0.40 0.33 0.27 loss 40% fail")
        XCTAssertTrue(p.thresholdIsOwn)
        XCTAssertEqual(p.threshold, 0.27)
        XCTAssertGreaterThan(try XCTUnwrap(p.oneRepMax), 120)   // a lower threshold, a heavier 1RM
    }

    func testReadinessAgainstTheLine() throws {
        let p = try profile(clean)
        let day = records("2026-10-30 squat set 1 100x3 mcv 0.53 0.52 loss 2%")[0]
        XCTAssertEqual(try XCTUnwrap(p.readiness(day)), 6, accuracy: 1e-6)    // 0.53 against 0.50
    }

    func testLoadsForRoundSpeeds() throws {
        let t = try profile(clean).loadsForSpeeds
        XCTAssertEqual(t.map(\.speed), [0.70, 0.55, 0.40])
        XCTAssertEqual(t.map(\.load), [80, 95, 110])
    }

    func testTheRealSquatsSoFarSayWhatIsMissing() {
        // The owner's two measured squats: 105 and 110 kg, under 10% apart.
        let real = records("""
        2026-09-27 squat set 1 105x8 mcv 0.55 0.55 0.54 0.56 0.53 0.50 0.53 0.51 loss 9%
        2026-10-06 squat set 3 110x12 mcv 0.39 0.41 0.42 0.41 0.37 0.36 0.37 0.35 0.35 0.33 0.35 0.32 loss 24%
        """)
        guard case .needsMore(let why) = LoadVelocityProfile.fit(real, lift: "squat", now: now) else { return XCTFail() }
        XCTAssertTrue(why.contains("1 more measured set"), why)
        XCTAssertTrue(why.contains("10% apart"), why)
    }

    func testAllAtOneLoadAsksForAnotherLoad() {
        let same = records("""
        2026-10-01 squat set 1 100x5 mcv 0.50 0.48 loss 4%
        2026-10-01 squat set 2 100x5 mcv 0.49 0.47 loss 4%
        2026-10-08 squat set 1 102.5x5 mcv 0.48 0.46 loss 4%
        """)
        guard case .needsMore(let why) = LoadVelocityProfile.fit(same, lift: "squat", now: now) else { return XCTFail() }
        XCTAssertTrue(why.contains("10% lighter or heavier"), why)
    }

    func testOnlyTheLastTwelveWeeksCount() throws {
        // A set from May, far slower at 80 kg, would bend the line: it is left out.
        let p = try profile("2026-05-01 squat set 1 80x5 mcv 0.30 0.28 loss 7%\n" + clean)
        XCTAssertEqual(p.points.count, 4)
        XCTAssertEqual(p.slope, -0.01, accuracy: 1e-9)
    }

    func testBodyweightSetsAndNoSetsMakeNoProfile() {
        XCTAssertEqual(LoadVelocityProfile.fit([], lift: "squat"), .none)
        XCTAssertEqual(LoadVelocityProfile.fit(records("2026-10-01 chin-ups set 1 bwx8 mcv 0.6 0.5 loss 17%"), lift: "chin-ups"), .none)
    }

    func testCoachLine() throws {
        let p = try profile(clean)
        let ready = LoadVelocityProfile.readiness(records(clean), lift: "squat", now: now)
        let line = p.coachLine(lift: "squat", readiness: ready)
        XCTAssertTrue(line.contains("est. 1RM ≈ 120 kg at 0.30 m/s (typical threshold)"), line)
        XCTAssertTrue(line.contains("latest day's first set, 110 kg: on the profile"), line)
        XCTAssertTrue(line.contains("0.55 m/s ≈ 95 kg"), line)
    }

    // MARK: - From the review

    func testSetsCloseInLoadThatDontLineUpGiveNoProfile() {
        // Three squats 100–120 kg at about the same speed: once a "1RM ≈ 510 kg".
        let flat = "2026-10-01 squat set 1 100x5 mcv 0.50 loss 0%\n2026-10-08 squat set 1 110x5 mcv 0.51 loss 0%\n2026-10-15 squat set 1 120x5 mcv 0.49 loss 0%"
        guard case .needsMore(let why) = fit(flat) else { return XCTFail("a flat set of points made a profile") }
        XCTAssertTrue(why.contains("don't fall on a line"), why)
    }

    func testNoOneRepMaxBeyondThirtyPercentOfTheHeaviest() throws {
        // A clear but shallow line: its 1RM would be 200 kg off sets up to 110.
        let shallow = """
        2026-10-01 squat set 1 80x5 mcv 0.70 loss 0%
        2026-10-08 squat set 1 90x5 mcv 0.665 loss 0%
        2026-10-15 squat set 1 100x5 mcv 0.63 loss 0%
        2026-10-22 squat set 1 110x5 mcv 0.595 loss 0%
        """
        let p = try profile(shallow)
        XCTAssertTrue(p.isClear)
        XCTAssertNil(p.oneRepMax)
    }

    func testAHeavySetAtTheThresholdIsTheOneRepMax() throws {
        let heavy = clean + "\n2026-10-29 squat set 1 125x1 mcv 0.28 loss 0%"
        let p = try profile(heavy)
        XCTAssertEqual(try XCTUnwrap(p.oneRepMax), 125, accuracy: 3)
    }

    func testOldSetsAreJudgedFromTodayNotFromTheNewestSet() {
        let old = clean.replacingOccurrences(of: "2026-10", with: "2025-01")
        guard case .needsMore(let why) = fit(old) else { return XCTFail("a profile from January 2025") }
        XCTAssertTrue(why.contains("No measured sets in the last 12 weeks"), why)
    }

    func testTypicalThresholdByTheLogsOwnNames() {
        XCTAssertEqual(LoadVelocityProfile.typicalThreshold("ohp"), 0.19)
        XCTAssertEqual(LoadVelocityProfile.typicalThreshold("dl"), 0.15)
        XCTAssertEqual(LoadVelocityProfile.typicalThreshold("bench"), 0.17)
        XCTAssertNil(LoadVelocityProfile.typicalThreshold("leg-press"))
        XCTAssertNil(LoadVelocityProfile.typicalThreshold("dumbbell-shoulder-press"))
        XCTAssertNil(LoadVelocityProfile.typicalThreshold("bulgarian-split-squat"))
    }

    func testReadinessIsJudgedWithoutItsOwnDay() throws {
        // The profile from the first three; the new day's first set 6% faster than it predicts.
        let day = clean.split(separator: "\n").prefix(3).joined(separator: "\n")
            + "\n2026-10-30 squat set 1 100x3 mcv 0.53 0.52 loss 2%\n2026-10-30 squat set 2 110x3 mcv 0.30 loss 0%"
        let r = try XCTUnwrap(LoadVelocityProfile.readiness(records(day), lift: "squat", now: now))
        XCTAssertEqual(r.record.load, 100)
        XCTAssertEqual(r.percent, 6, accuracy: 1e-6)
        XCTAssertEqual(LoadVelocityProfile.readinessText(r.percent), "6% faster than the profile")
        XCTAssertEqual(LoadVelocityProfile.readinessText(-0.4), "on the profile")
    }

    func testAbsurdNumbersDontCrash() {
        XCTAssertNil(VelocitySet(url: URL(string: "grepp://velocity?v=1&lift=squat&load=1e300&mcv=0.5")!))
        XCTAssertEqual(WorkSet.formatWeight(.infinity), "inf")
        XCTAssertNil(records("2026-10-01 squat set 1 100x5 mcv 0.5 v1rm 1e30")[0].v1rm)
    }

    func testAnyRulerNameReadsBack() {
        let r = records("2026-10-01 squat set 1 100x5 mcv 0.5 loss 0% scale ±1.2% bar v1rm 120")[0]
        XCTAssertEqual(r.rulers, ["bar"])
        XCTAssertEqual(r.v1rm, 120)
    }
}
