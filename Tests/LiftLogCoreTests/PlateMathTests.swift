import XCTest
@testable import LiftLogCore

final class PlateMathTests: XCTestCase {

    // A home rack: no 20s, and micro plates. Four 25s is two a side.
    private let home = PlateInventory(counts: [25: 4, 15: 2, 10: 2, 5: 2, 2.5: 2, 1.25: 2, 0.5: 2, 0.25: 2])

    // MARK: - the standard rack

    func testExactLoadsLargestPlateFirst() {
        XCTAssertEqual(PlateMath.load(60)?.perSide, [20])
        XCTAssertEqual(PlateMath.load(87.5)?.perSide, [25, 5, 2.5, 1.25])
        XCTAssertEqual(PlateMath.load(87.5)?.isApproximate, false)
    }

    func testTiesGoToFewestThenHeaviestPlates() {
        // 80 a side: [25,25,25,5] and [20,20,20,20] are both four plates.
        XCTAssertEqual(PlateMath.load(180)?.perSide, [25, 25, 25, 5])
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
        // The standard rack has no 0.5: 86 needs 33 a side, and 32.5 is the best it can do.
        let load = PlateMath.load(86)
        XCTAssertEqual(load?.perSide, [25, 5, 2.5])
        XCTAssertEqual(load?.isApproximate, true)
        XCTAssertEqual(load?.total, 85)
    }

    // MARK: - your own rack

    func testHomeRackNeverSuggestsAPlateYouDontOwn() {
        // 60 on a 20 bar is 20 a side — and there is no 20 plate.
        XCTAssertEqual(PlateMath.load(60, inventory: home)?.perSide, [15, 5])
        XCTAssertEqual(PlateMath.load(87.5, bar: 15, inventory: home)?.perSide, [25, 10, 1.25])
    }

    func testMicroPlatesAreUsed() {
        XCTAssertEqual(PlateMath.load(65.5, bar: 15, inventory: home)?.perSide, [25, 0.25])
        XCTAssertEqual(PlateMath.load(65.5, bar: 15, inventory: home)?.isApproximate, false)
    }

    func testAPairIsNeededToLoadASide() {
        // Three 25s is one usable pair; the odd one out can't go on one side alone.
        let three = PlateInventory(counts: [25: 3, 5: 2])
        XCTAssertEqual(PlateMath.load(70, inventory: three)?.perSide, [25])
        XCTAssertEqual(PlateMath.load(120, inventory: three)?.isApproximate, true, "two 25s a side would need four")
    }

    func testSearchFindsWhatGreedyMisses() {
        // One 15 and two 10s a side, 20 to load: greedy takes the 15 and is stuck at 15.
        let rack = PlateInventory(counts: [15: 2, 10: 4])
        let load = PlateMath.load(60, inventory: rack)
        XCTAssertEqual(load?.perSide, [10, 10])
        XCTAssertEqual(load?.isApproximate, false)
    }

    func testRunningOutOfPlatesIsApproximate() {
        let load = PlateMath.load(200, inventory: home)   // 90 a side; the rack tops out lower
        XCTAssertEqual(load?.isApproximate, true)
        XCTAssertEqual(load?.perSide, [25, 25, 15, 10, 5, 2.5, 1.25, 0.5, 0.25])
    }

    // MARK: - storage and labels

    func testInventoryRoundTripsThroughItsRawValue() {
        let back = PlateInventory(rawValue: home.rawValue)
        XCTAssertEqual(back, home)
        XCTAssertEqual(PlateInventory(rawValue: "25:4,nonsense,1.25:2")?.counts, [25: 4, 1.25: 2],
                       "a bad pair is skipped, not fatal")
    }

    func testLabelsKeepTwoDecimalsWhenTheyMatter() {
        XCTAssertEqual(PlateMath.label(25), "25")
        XCTAssertEqual(PlateMath.label(2.5), "2.5")
        XCTAssertEqual(PlateMath.label(1.25), "1.25")
        XCTAssertEqual(PlateMath.label(0.25), "0.25")
    }
}
