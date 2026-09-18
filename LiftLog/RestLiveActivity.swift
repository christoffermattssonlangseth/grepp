import ActivityKit
import Foundation

/// Puts the rest clock on the lock screen and in the Dynamic Island.
///
/// One activity at a time, kept in step with the in-app clock: started when a
/// set lands, updated when the target changes or the next lift's set lands,
/// ended when the rest ends. The system draws the countdown from the dates,
/// so nothing here needs the app awake. The stale date is the target, which is
/// how the widget knows to flip to READY without an update from us.
///
/// Anything left over from a session that ended without the app noticing —
/// the phone died, the draft aged out — is ended on the next launch, because
/// the Log screen syncs on appear whether or not a rest is running.
@MainActor
enum RestLiveActivity {
    static func sync(start: Date?, target: Int, exercise: String, nextUp: String?, landLabel: String?) {
        Task { await syncAndWait(start: start, target: target, exercise: exercise, nextUp: nextUp, landLabel: landLabel) }
    }

    /// The same, finished before it returns — for the intent, which must not
    /// return before the lock screen has its clock.
    static func syncAndWait(start: Date?, target: Int, exercise: String, nextUp: String?, landLabel: String?) async {
        guard let start else { await endAndWait(); return }
        let end = max(start.addingTimeInterval(TimeInterval(target)), start)
        let state = RestActivityAttributes.ContentState(exercise: exercise, start: start,
                                                        end: end, nextUp: nextUp, landLabel: landLabel)
        let content = ActivityContent(state: state, staleDate: end)

        // Past its stale date — the countdown reached READY — the activity is
        // "stale", not "active", and it is still ours to update: the next set's
        // rest goes into it. Asking for a new one instead is refused while the
        // old one is up, which left READY on the lock screen all session.
        let live = Activity<RestActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        if let current = live.first {
            await current.update(content)
            for extra in live.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // A refusal here (the user has Live Activities off, or too many are up)
        // is not worth a message — the in-app clock and the notification stand.
        _ = try? Activity<RestActivityAttributes>.request(attributes: RestActivityAttributes(),
                                                          content: content, pushType: nil)
    }

    static func end() {
        Task { await endAndWait() }
    }

    static func endAndWait() async {
        for activity in Activity<RestActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// Everything outside the app that mirrors the rest clock — the Live Activity
/// and the "rest's up" notification — driven from one place by the draft, so
/// the Log screen and a lock-screen tap keep them in step the same way.
@MainActor
enum RestSignals {
    /// The rest target, as the Log screen keeps it. Nonisolated because it's
    /// the default for `sync`, and default arguments are evaluated outside
    /// the actor; it only reads a value UserDefaults guards itself.
    nonisolated static var target: Int {
        let stored = UserDefaults.standard.integer(forKey: Prefs.restTarget)
        return stored > 0 ? stored : 90
    }

    static func sync(_ draft: SessionDraft?, target: Int = RestSignals.target) {
        Task { await syncAndWait(draft, target: target) }
    }

    /// Finished before it returns; the intent needs that.
    static func syncAndWait(_ draft: SessionDraft?, target: Int = RestSignals.target) async {
        guard let draft, let start = draft.restStart else {
            await RestLiveActivity.endAndWait()
            RestNotifier.cancel()
            return
        }
        let exercise = Theme.readableName(draft.name)
        let next = draft.nextPlanned.map { "\($0.loadLabel) × \($0.reps)" }
        let land = draft.sameAgainSet.map { "\($0.loadLabel) × \($0.reps)" }
        await RestLiveActivity.syncAndWait(start: start, target: target, exercise: exercise,
                                           nextUp: next, landLabel: land)

        let remaining = target - Int(Date().timeIntervalSince(start))
        guard remaining > 0 else { RestNotifier.cancel(); return }
        await RestNotifier.schedule(in: remaining, next: next.map { "\(exercise) · \($0)" })
    }
}
