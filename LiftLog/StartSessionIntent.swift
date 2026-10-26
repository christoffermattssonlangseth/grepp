import AppIntents

/// Starts today's session clock: for a Shortcuts automation that runs on
/// arriving at the gym, or a tap before the warm-up. The app installs
/// `handler` at launch, as with `SameAgainIntent`.
nonisolated struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start session"
    static var description = IntentDescription(
        "Starts today's session clock in Grepp, so the warm-up counts. A clock already running is left alone.")
    static var openAppWhenRun = false
    /// An arrival automation runs with the phone in a pocket, locked.
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor static var handler: (() -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { Self.handler?() }
        return .result()
    }
}
