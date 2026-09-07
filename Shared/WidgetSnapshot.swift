import Foundation

/// What the home screen widget shows: the last session, pre-rendered.
///
/// The widget never parses `training.md` — the app writes this small record
/// into the shared App Group whenever the sessions change, and the widget reads
/// it. That keeps the widget target free of the app's parser and the GitHub
/// token, which stays in the app's Keychain where it belongs.
struct WidgetSnapshot: Codable, Equatable {
    struct Line: Codable, Equatable {
        var name: String
        /// The set tokens as the log has them: "87.5x5 87.5x5 87.5x5".
        var sets: String
    }

    /// The day, as the log keys it: yyyy-MM-dd.
    var day: String
    var lines: [Line]
    /// What's loaded in the Log tab and not yet lifted: the lift in the fields
    /// with its plan, then the queue Coach handed over. Empty when nothing is.
    var plan: [Line]? = []

    var upNext: [Line] { plan ?? [] }

    /// Shared between the app and the widget. Must match both entitlements files.
    static let appGroup = "group.CML.LiftLog"
    /// The widget kind, for `WidgetCenter.reloadTimelines(ofKind:)`.
    static let kind = "LastSession"
    private static let key = "widget_snapshot"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Nil clears it — no sessions, nothing to show.
    static func save(_ snapshot: WidgetSnapshot?) {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else {
            defaults?.removeObject(forKey: key)
            return
        }
        defaults?.set(data, forKey: key)
    }

    /// The day as a date at local midnight — what a calendar wants.
    var date: Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }

    /// Placeholder content for the widget gallery and previews.
    static let sample = WidgetSnapshot(day: "2026-09-04", lines: [
        Line(name: "squat", sets: "87.5x5 87.5x5 87.5x5"),
        Line(name: "bench", sets: "70x5 70x5 70x5"),
        Line(name: "chin-ups", sets: "bw+5x6 bw+5x6 bw+5x5"),
    ], plan: [
        Line(name: "deadlift", sets: "120x5 120x5 120x5"),
        Line(name: "over-head-press", sets: "45x5 45x5 45x5"),
    ])
}
