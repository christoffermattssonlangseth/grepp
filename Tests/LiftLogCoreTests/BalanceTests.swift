import XCTest
@testable import LiftLogCore

final class BalanceTests: XCTestCase {

    func testPushPullAndQuadsHamstringsAreAveragedAndJudged() {
        let weeks: [MuscleMap.Credits] = [
            [.chest: 8, .triceps: 4, .frontDelts: 4, .back: 6, .biceps: 2, .quads: 6, .hamstrings: 6],
            [.chest: 8, .triceps: 4, .frontDelts: 4, .back: 6, .biceps: 2, .quads: 6, .hamstrings: 3],
        ]
        let pairs = Balance.pairs(over: weeks)
        XCTAssertEqual(pairs.map(\.id), ["push-pull", "quads-hamstrings"])
        XCTAssertEqual(pairs[0].a.sets, 16)
        XCTAssertEqual(pairs[0].b.sets, 8)
        XCTAssertEqual(pairs[0].short?.name, "pull")
        XCTAssertEqual(pairs[0].verdict, "pull is short")
        XCTAssertEqual(pairs[1].a.sets, 6)
        XCTAssertEqual(pairs[1].b.sets, 4.5)
        XCTAssertNil(pairs[1].short, "4.5 is over seven tenths of six, so even")
        XCTAssertEqual(pairs[1].verdict, "even")
    }

    func testTooFewSetsIsNotAVerdict() {
        let pairs = Balance.pairs(over: [[.chest: 2, .back: 0.5]])
        XCTAssertNil(pairs[0].short)
        XCTAssertEqual(pairs[0].verdict, "too few sets to read")
        XCTAssertEqual(Balance.pairs(over: []), [])
    }
}
