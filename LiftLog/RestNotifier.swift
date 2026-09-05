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
    static func schedule(in seconds: Int, next: String?) {
        let center = UNUserNotificationCenter.current()
        let id = Self.id   // captured up front: the closure below is @Sendable
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard seconds > 0 else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest's up"
            content.body = next.map { "Next: \($0)" } ?? "Back to it."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
