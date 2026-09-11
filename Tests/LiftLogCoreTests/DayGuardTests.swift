import XCTest
@testable import LiftLogCore

final class DayGuardTests: XCTestCase {

    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func at(_ s: String) -> Date {
        let f = ISO8601DateFormatter(); return f.date(from: s)!
    }

    func testTodayNeverAsks() {
        XCTAssertFalse(DayGuard.needsCheck(date: at("2026-09-10T09:00:00Z"), chosen: false, sessionStart: nil,
                                           now: at("2026-09-10T18:00:00Z"), calendar: utc))
    }

    func testAnUnchosenOldDayAsks() {
        XCTAssertTrue(DayGuard.needsCheck(date: at("2026-09-09T09:00:00Z"), chosen: false, sessionStart: nil,
                                          now: at("2026-09-10T18:00:00Z"), calendar: utc))
    }

    func testAChosenDayIsTrusted() {
        XCTAssertFalse(DayGuard.needsCheck(date: at("2026-09-01T09:00:00Z"), chosen: true, sessionStart: nil,
                                           now: at("2026-09-10T18:00:00Z"), calendar: utc))
    }

    func testASessionThatRanPastMidnightStaysItsDay() {
        let yesterday = at("2026-09-09T23:40:00Z")
        XCTAssertFalse(DayGuard.needsCheck(date: yesterday, chosen: false, sessionStart: yesterday,
                                           now: at("2026-09-10T00:20:00Z"), calendar: utc))
        XCTAssertTrue(DayGuard.needsCheck(date: yesterday, chosen: false, sessionStart: yesterday,
                                          now: at("2026-09-10T09:00:00Z"), calendar: utc),
                      "nine hours on, it is a new day")
    }

    func testResetOnlyWhenIdleUnchosenAndStale() {
        let old = at("2026-09-09T09:00:00Z"), now = at("2026-09-10T18:00:00Z")
        XCTAssertTrue(DayGuard.shouldReset(date: old, chosen: false, idle: true, now: now, calendar: utc))
        XCTAssertFalse(DayGuard.shouldReset(date: old, chosen: true, idle: true, now: now, calendar: utc), "picked on purpose")
        XCTAssertFalse(DayGuard.shouldReset(date: old, chosen: false, idle: false, now: now, calendar: utc), "a lift in flight")
        XCTAssertFalse(DayGuard.shouldReset(date: now, chosen: false, idle: true, now: now, calendar: utc), "already today")
    }
}
