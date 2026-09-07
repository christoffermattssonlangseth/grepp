import Foundation

/// What a lifting session looks like on Strava: a "Weight Training" activity
/// whose description is the day's lines, exactly as the log has them.
///
/// Strava has no notion of sets or loads, so the description carries the
/// detail. Pure formatting, so it can be tested without a network.
enum StravaPost {
    /// The Strava sport type for a lifting session.
    static let sportType = "WeightTraining"

    /// The sign-off at the foot of every post. Strava turns the URL into a link.
    static let signOff = "Tracked with LiftLog — a plain-text lifting log with a Claude coach\nhttps://github.com/christoffermattssonlangseth/liftlog"

    /// "Lifting · squat, bench, chin-ups" — the first three lifts, then a count.
    static func name(for session: Session) -> String {
        let names = session.exercises.map { $0.name.replacingOccurrences(of: "-", with: " ") }
        guard !names.isEmpty else { return "Lifting" }
        let shown = names.prefix(3).joined(separator: ", ")
        let more = names.count > 3 ? " +\(names.count - 3)" : ""
        return "Lifting · \(shown)\(more)"
    }

    /// The lines from training.md minus the date, then a summary line.
    static func description(for session: Session, elapsed: TimeInterval?) -> String {
        let lines = session.exercises.map { "\($0.name) \($0.sets.map(\.token).joined(separator: " "))" }
        let sets = session.exercises.reduce(0) { $0 + $1.sets.count }
        var summary = "\(session.exercises.count) \(session.exercises.count == 1 ? "lift" : "lifts") · \(sets) \(sets == 1 ? "set" : "sets")"
        if let elapsed, elapsed >= 60 { summary += " · \(Int(elapsed / 60)) min" }
        return lines.joined(separator: "\n") + "\n\n" + summary + "\n\n" + signOff
    }

    /// Noon, local time, on the session's day — for a day the app never clocked
    /// (logged after the fact, or before the clock existed). Built from the
    /// log's own date key so it lands on the right day in any time zone.
    static func defaultStart(for session: Session, calendar: Calendar = .current) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        let midnight = f.date(from: session.dateString) ?? session.date
        return calendar.date(byAdding: .hour, value: 12, to: midnight) ?? midnight
    }

    /// Seconds the activity lasted. From the first set to the last push when
    /// both are known and sensible; an hour otherwise, since Strava wants a
    /// number and a guess beats a zero-length workout.
    static func elapsed(start: Date?, end: Date?) -> TimeInterval {
        guard let start, let end else { return 3600 }
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 60, seconds <= 6 * 3600 else { return 3600 }
        return seconds.rounded()
    }
}
