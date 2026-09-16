import XCTest
@testable import LiftLogCore

final class SpendLedgerTests: XCTestCase {

    private var calendar: Calendar { Session.calendar }
    private func day(_ s: String) -> Date { Session.dateFormatter.date(from: s)! }

    func testAnswersAddUpWithinTheirMonth() {
        var ledger = SpendLedger()
        ledger.add(0.04, on: day("2026-09-03"), calendar: calendar)
        ledger.add(0.06, on: day("2026-09-20"), calendar: calendar)
        ledger.add(1.00, on: day("2026-10-01"), calendar: calendar)
        ledger.add(0, on: day("2026-09-21"), calendar: calendar)
        XCTAssertEqual(ledger.total(for: day("2026-09-15"), calendar: calendar), 0.10, accuracy: 0.0001)
        XCTAssertEqual(ledger.total(for: day("2026-10-15"), calendar: calendar), 1.00, accuracy: 0.0001)
        XCTAssertEqual(ledger.total(for: day("2026-08-15"), calendar: calendar), 0)
    }

    func testTheCapBlocksOnlyOnceReachedAndNeverWhenOff() {
        var ledger = SpendLedger()
        ledger.add(9.99, on: day("2026-09-03"), calendar: calendar)
        XCTAssertNil(ledger.block(cap: 10, on: day("2026-09-10"), calendar: calendar))
        ledger.add(0.02, on: day("2026-09-10"), calendar: calendar)
        let why = ledger.block(cap: 10, on: day("2026-09-10"), calendar: calendar)
        XCTAssertNotNil(why)
        XCTAssertTrue(why?.contains("$10.01") ?? false, why ?? "")
        XCTAssertTrue(why?.contains("$10 cap") ?? false, why ?? "")
        XCTAssertNil(ledger.block(cap: 0, on: day("2026-09-10"), calendar: calendar), "no cap")
        XCTAssertNil(ledger.block(cap: 10, on: day("2026-10-01"), calendar: calendar), "a new month")
    }

    func testOnlyAYearOfMonthsIsKept() {
        var ledger = SpendLedger()
        for month in 1...14 {
            ledger.add(1, on: day(String(format: "%04d-%02d-10", 2025 + (month - 1) / 12, (month - 1) % 12 + 1)), calendar: calendar)
        }
        XCTAssertEqual(ledger.months.count, 12)
        XCTAssertNil(ledger.months["2025-01"])
        XCTAssertEqual(ledger.months["2026-02"], 1)
    }

    func testMoneyReadsLikeAPriceTag() {
        XCTAssertEqual(SpendLedger.money(10), "10")
        XCTAssertEqual(SpendLedger.money(3.456), "3.46")
    }
}
