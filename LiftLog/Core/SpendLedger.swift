import Foundation

/// What the Coach's cloud models have cost, month by month, as the app
/// estimates it from token counts. The ledger is the guardrail's memory:
/// a monthly cap is judged against it, and it never forgets a month early.
struct SpendLedger: Equatable, Codable {
    /// Dollars per month, keyed yyyy-MM in the phone's own calendar.
    var months: [String: Double] = [:]

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// Add one answer's cost to its month. Old months are kept for a year, so
    /// the number shown is never a surprise reset.
    mutating func add(_ dollars: Double, on date: Date, calendar: Calendar = .current) {
        guard dollars > 0 else { return }
        months[Self.monthKey(for: date, calendar: calendar), default: 0] += dollars
        if months.count > 12 {
            for key in months.keys.sorted().prefix(months.count - 12) { months.removeValue(forKey: key) }
        }
    }

    func total(for date: Date, calendar: Calendar = .current) -> Double {
        months[Self.monthKey(for: date, calendar: calendar)] ?? 0
    }

    /// Why a cloud answer must not be sent now, or nil when it may. A cap of
    /// zero means no cap.
    func block(cap: Double, on date: Date, calendar: Calendar = .current) -> String? {
        guard cap > 0 else { return nil }
        let spent = total(for: date, calendar: calendar)
        guard spent >= cap else { return nil }
        return "The Coach has spent about $\(Self.money(spent)) this month, which is past the $\(Self.money(cap)) cap in Settings ▸ Coach. Raise the cap there, use the on-device model, or wait for the 1st."
    }

    static func money(_ dollars: Double) -> String {
        dollars == dollars.rounded() ? String(Int(dollars)) : String(format: "%.2f", dollars)
    }
}
