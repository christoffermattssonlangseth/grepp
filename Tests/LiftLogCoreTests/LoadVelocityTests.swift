import XCTest
@testable import LiftLogCore

final class LoadVelocityTests: XCTestCase {
    private func records(_ text: String) -> [VelocityRecord] {
        VelocityRecord.parse(text)
    }
    private func profile(_ text: String, lift: String = "squat") throws -> LoadVelocityProfile {
        guard case .profile(let p) = LoadVelocityProfile.fit(records(text), lift: lift) else {
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
        guard case .needsMore(let why) = LoadVelocityProfile.fit(real, lift: "squat") else { return XCTFail() }
        XCTAssertTrue(why.contains("1 more measured set"), why)
        XCTAssertTrue(why.contains("10% apart"), why)
    }

    func testAllAtOneLoadAsksForAnotherLoad() {
        let same = records("""
        2026-10-01 squat set 1 100x5 mcv 0.50 0.48 loss 4%
        2026-10-01 squat set 2 100x5 mcv 0.49 0.47 loss 4%
        2026-10-08 squat set 1 102.5x5 mcv 0.48 0.46 loss 4%
        """)
        guard case .needsMore(let why) = LoadVelocityProfile.fit(same, lift: "squat") else { return XCTFail() }
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
        let latest = records(clean).last
        let line = p.coachLine(lift: "squat", latest: latest)
        XCTAssertTrue(line.contains("est. 1RM ≈ 120 kg at 0.30 m/s (typical threshold)"), line)
        XCTAssertTrue(line.contains("latest set at 110 kg +0% vs profile"), line)
        XCTAssertTrue(line.contains("0.55 m/s ≈ 95 kg"), line)
    }
}
