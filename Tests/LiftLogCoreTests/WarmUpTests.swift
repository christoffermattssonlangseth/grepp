import XCTest
@testable import LiftLogCore

final class WarmUpTests: XCTestCase {

    func testAHundredRampsInFourRungsWithPlates() {
        let rungs = WarmUp.ramp(to: 100)!
        XCTAssertEqual(rungs.map(\.weight), [20, 50, 70, 85])
        XCTAssertEqual(rungs.map(\.reps), [10, 5, 3, 1])
        XCTAssertEqual(rungs.map(\.perSide), [[], [15], [25], [25, 7.5]])
        XCTAssertEqual(WarmUp.line(rungs, bar: 20), "bar ×10 · 50 (15) ×5 · 70 (25) ×3 · 85 (25+7.5) ×1")
    }

    func testRungsRoundDownToTheRackAndSkipTheBar() {
        // 87.5: 43.75 → 42.5, 61.25 → 60, 74.4 → 72.5.
        XCTAssertEqual(WarmUp.ramp(to: 87.5)?.map(\.weight), [20, 42.5, 60, 72.5])
        // 40: half is the bar itself, so the ramp is the bar, 27.5 and 32.5.
        XCTAssertEqual(WarmUp.ramp(to: 40)?.map(\.weight), [20, 27.5, 32.5])
        XCTAssertEqual(WarmUp.ramp(to: 40)?.map(\.reps), [10, 3, 1])
    }

    func testNothingToRampToAtOrUnderTheBar() {
        XCTAssertNil(WarmUp.ramp(to: 20))
        XCTAssertNil(WarmUp.ramp(to: 15))
        // Just over the bar: the bar alone, no rung lands between.
        XCTAssertEqual(WarmUp.ramp(to: 22.5)?.map(\.weight), [20])
    }

    func testAnotherBarAndAThinRack() {
        // A 15 kg bar and only 10s and 5s: 60 → 30 (not 30? 30 needs 7.5 a side) …
        let rack = PlateInventory(counts: [10: 4, 5: 4])
        let rungs = WarmUp.ramp(to: 65, bar: 15, inventory: rack)!
        // Half of 65 is 32.5; with 10s and 5s a side from a 15 bar the nearest
        // under is 25 (5 a side). 45.5 → 45 exactly (15 a side); 55.25 → 55 (20).
        XCTAssertEqual(rungs.map(\.weight), [15, 25, 45, 55])
        XCTAssertEqual(rungs[1].perSide, [5])
        XCTAssertEqual(rungs[3].perSide, [10, 10])
        XCTAssertTrue(WarmUp.line(rungs, bar: 15).hasPrefix("bar ×10 · 25 (5) ×5"))
    }
}
