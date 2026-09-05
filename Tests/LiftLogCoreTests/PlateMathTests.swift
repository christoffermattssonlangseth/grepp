import XCTest
@testable import LiftLogCore

final class PlateMathTests: XCTestCase {

    func testExactLoadsLargestPlateFirst() {
        XCTAssertEqual(PlateMath.load(60)?.perSide, [20])
        XCTAssertEqual(PlateMath.load(87.5)?.perSide, [25, 5, 2.5, 1.25])
        XCTAssertEqual(PlateMath.load(180)?.perSide, [25, 25, 25, 5], "largest first, like a lifter")
        XCTAssertEqual(PlateMath.load(87.5)?.isApproximate, false)
    }

    func testTheBarAloneIsALoad() {
        let load = PlateMath.load(20)
        XCTAssertEqual(load?.perSide, [])
        XCTAssertEqual(load?.total, 20)
    }

    func testLighterThanTheBarIsNothing() {
        XCTAssertNil(PlateMath.load(15))
    }

    func testUnmakeableWeightIsNearestBelowAndSaysSo() {
        let load = PlateMath.load(86)
        XCTAssertEqual(load?.perSide, [25, 5, 2.5])
        XCTAssertEqual(load?.isApproximate, true)
        XCTAssertEqual(load?.total, 85)
    }

    func testBarWeightIsHonoured() {
        XCTAssertEqual(PlateMath.load(60, bar: 15)?.perSide, [20, 2.5])
        XCTAssertEqual(PlateMath.load(60, bar: 15)?.total, 60)
    }

    func testFloatingPointDoesNotLoseTheSmallPlate() {
        // 33.75 - 25 - 5 - 2.5 is 1.2499999… in binary; the 1.25 must still load.
        XCTAssertEqual(PlateMath.load(87.5)?.total, 87.5)
    }
}
