import AppIntents

/// The one button on the lock screen: land the next set without unlocking.
///
/// A Live Activity intent runs in the *app's* process — the system wakes the
/// app in the background to perform it — so the extension only has to name
/// it, and the app decides what it does. The app installs `handler` at launch;
/// in the extension it stays nil, and the extension never performs it anyway.
nonisolated struct SameAgainIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Same again"
    static var description = IntentDescription(
        "Lands the next planned set, or repeats the last one, and restarts the rest clock.")
    static var openAppWhenRun = false
    static var isDiscoverable = false
    /// Runs from the lock screen without unlocking: the default policy wants
    /// authentication, which on a locked phone turns the tap into nothing.
    /// Landing one more set of the lift you're already doing is fine unlocked.
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    /// Async, and awaited: when the phone is locked the system launches the
    /// app just to run this and may suspend it the moment `perform` returns,
    /// so the lock-screen update and the notification must be done by then.
    @MainActor static var handler: (() async -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        if let handler = await Self.handler { await handler() }
        return .result()
    }
}
