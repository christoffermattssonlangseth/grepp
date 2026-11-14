import AppIntents

/// The one button on the lock screen: land the next set without unlocking.
/// The Last session widget has it too, as "+ squat 100x5".
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
    @MainActor static var handler: ((_ fromWidget: Bool) async -> Void)?

    /// Pressed on the widget rather than the rest timer. The timer's button
    /// ends a rest left running for half an hour instead of landing a set; on
    /// the widget, which names the set it lands, a press always lands it.
    @Parameter(title: "From widget") var fromWidget: Bool

    init() { fromWidget = false }
    init(fromWidget: Bool) { self.fromWidget = fromWidget }

    func perform() async throws -> some IntentResult {
        if let handler = await Self.handler { await handler(fromWidget) }
        return .result()
    }
}
