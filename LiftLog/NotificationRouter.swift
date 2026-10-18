import UserNotifications

/// Where a tapped notification lands. "Coach answered" opens Coach, where the
/// answer is; anything else opens the app as it was.
///
/// Only the tap is handled: with no `willPresent`, a notification that arrives
/// while the app is open stays silent, as it did before there was a delegate.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    static let coachAnswer = "coach-answer"

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Self.coachAnswer else { return }
        await MainActor.run { Store.shared.selectedTab = 3 }
    }
}
