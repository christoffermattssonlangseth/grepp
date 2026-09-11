import Foundation

/// The rules for the date a set is about to land under. The Log screen asks
/// these before a set lands and when it comes back to the front; they live
/// here so they can be tested without a screen.
enum DayGuard {
    /// A session that started this long ago is still the same session:
    /// finishing after midnight belongs to the day it began.
    static let sameSessionWindow: TimeInterval = 8 * 3600

    /// Should a set landing under `date` be questioned? Yes when the day
    /// isn't today, nobody picked it, and it isn't a session that ran past
    /// midnight (its first set landed within the window).
    static func needsCheck(date: Date, chosen: Bool, sessionStart: Date?,
                           now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if chosen || calendar.isDate(date, inSameDayAs: now) { return false }
        if let start = sessionStart, now.timeIntervalSince(start) < sameSessionWindow, start <= now {
            return false
        }
        return true
    }

    /// Should an idle Log screen snap its date back to today? Only with
    /// nothing in flight and no date anyone chose.
    static func shouldReset(date: Date, chosen: Bool, idle: Bool,
                            now: Date = Date(), calendar: Calendar = .current) -> Bool {
        idle && !chosen && !calendar.isDate(date, inSameDayAs: now)
    }
}
