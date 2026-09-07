import Foundation

/// Posting one logged day to Strava, from wherever the button is: Log for
/// today, History for an older day, Settings for everything not yet posted.
/// Creates the activity the first time and updates it after that, keyed by
/// the day in the store.
@MainActor
enum StravaPoster {
    enum Outcome { case posted, updated }

    @discardableResult
    static func post(_ session: Session, store: Store, strava: StravaService) async throws -> Outcome {
        let clocked = store.sessionStart(on: session.date)
        let start = clocked ?? StravaPost.defaultStart(for: session)
        // Today's clock runs to now; an older day gets the hour default.
        let end = clocked != nil && Calendar.current.isDateInToday(start) ? Date() : nil
        let elapsed = StravaPost.elapsed(start: clocked, end: end)
        let name = StravaPost.name(for: session)
        let description = StravaPost.description(for: session, elapsed: end != nil ? elapsed : nil)

        if let id = store.stravaActivity(on: session.date) {
            try await strava.update(id: id, name: name, description: description)
            return .updated
        }

        // Strava refuses a second activity over the same time (409). A clocked
        // day is genuinely there already; a guessed noon just needs to move —
        // an hour later, up to three times, still on the same day.
        var attempt = start
        for shift in 0...3 {
            do {
                let id = try await strava.post(name: name, description: description, start: attempt, elapsed: elapsed)
                store.setStravaActivity(id, on: session.date)
                return .posted
            } catch StravaService.StravaError.api(let status, _) where status == 409 && clocked == nil && shift < 3 {
                attempt = start.addingTimeInterval(TimeInterval(shift + 1) * 3600)
            }
        }
        throw StravaService.StravaError.api(status: 409, message: "")
    }
}
