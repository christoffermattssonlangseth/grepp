import UserNotifications

/// Tells you rest is up when the phone is locked or you're in another app.
///
/// In the foreground the card flip and the haptic cover it, and iOS drops a
/// banner for a foregrounded app by default, so there's never a double alert.
/// One pending notification at a time, always under the same identifier, so
/// rescheduling replaces rather than stacks.
enum RestNotifier {
    private static let id = "rest-due"

    /// Schedule for `seconds` from now, replacing any pending one. Asks for
    /// permission on the way — the system prompts once and is silent after,
    /// so this can be called every time a rest starts.
    static func schedule(in seconds: Int, next: String?) async {
        let center = UNUserNotificationCenter.current()
        let id = Self.id
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        guard seconds > 0 else { return }

        // Awaited, not a callback: the lock-screen intent returns only when
        // this is scheduled, or the process may be suspended with it pending.
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = next.map { "Next: \($0)" } ?? "Back to it."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Pending and delivered both: a rest that ended by hand shouldn't leave
    /// "Rest's up" sitting in Notification Centre.
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
