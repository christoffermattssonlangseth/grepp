import XCTest
@testable import LiftLogCore

final class VelocitySessionTests: XCTestCase {

    // The owner's bench on 7 Nov, as velocity.md has it.
    private let bench = """
    2026-10-31 bench-press set 1 72.5x8 mcv 0.40 0.30 loss 25%
    2026-11-07 bench-press set 1 73.5x8 mcv 0.39 0.35 0.34 0.34 0.32 0.30 0.27 0.23 loss 41% scale ±3% bar
    2026-11-07 bench-press set 2 73.5x8 mcv 0.37 0.34 0.32 0.31 0.29 0.26 0.25 0.23 loss 39% scale ±3% bar
    2026-11-07 bench-press set 3 73.5x12 mcv 0.40 0.37 0.36 0.34 0.32 0.30 0.27 0.26 0.24 0.21 0.21 0.19 loss 53% left 0 scale ±3% bar
    """

    private func session(_ text: String, lift: String = "bench-press") throws -> VelocitySession {
        let records = VelocityRecord.records(for: lift, in: VelocityRecord.parse(text))
        return try XCTUnwrap(VelocitySession.latest(records, lift: lift, model: ReserveModel.fit(records)))
    }

    func testTheOwnersBenchSession() throws {
        let s = try session(bench)
        XCTAssertEqual(s.date, Session.dateFormatter.date(from: "2026-11-07"))
        XCTAssertEqual(s.rows.count, 3)
        XCTAssertEqual(s.target, 0.40)
        // 41% and 53% past 40%; 39% not.
        XCTAssertEqual(s.rows.map(\.pastTarget), [true, false, true])
        XCTAssertEqual(s.targetLine, "stop target 40%: 2 of 3 sets went past it")
        XCTAssertEqual(s.rows[2].text, "set 3 · 73.5×12 · 0.40 → 0.19 · −53% · 0 left")
        // One answered set: no model, so no estimate on the others.
        XCTAssertEqual(s.rows[0].text, "set 1 · 73.5×8 · 0.39 → 0.23 · −41%")
        XCTAssertNil(s.rows[0].reserve)
        XCTAssertEqual(try XCTUnwrap(s.rows[2].firstRepChange), (0.40 - 0.39) / 0.39 * 100, accuracy: 1e-9)
        XCTAssertEqual(s.fatigueLine, "fastest rep, last set against the first: +3%")
    }

    func testRowsAndFailAndTargets() throws {
        let s = try session("""
        2026-11-07 seal-row set 1 62.5x12 mcv 0.80 0.65 loss 19%
        2026-11-07 seal-row set 2 62.5x12 mcv 0.70 0.40 loss 43% fail
        """, lift: "seal-row")
        XCTAssertEqual(s.target, 0.35)
        XCTAssertEqual(s.rows[1].text, "set 2 · 62.5×12 · 0.70 → 0.40 · −43% · fail")
        XCTAssertEqual(s.targetLine, "stop target 35%: 1 of 2 sets went past it")
        XCTAssertEqual(s.fatigueLine, "fastest rep, last set against the first: −13%")
        let one = try session("2026-11-07 squat set 1 92.5x10 mcv 0.58 0.47 loss 19%", lift: "squat")
        XCTAssertNil(one.fatigueLine)
        XCTAssertEqual(one.targetLine, "stop target 35%: no set went past it")
        XCTAssertNil(VelocitySession.latest([], lift: "squat", model: nil))
    }
}
