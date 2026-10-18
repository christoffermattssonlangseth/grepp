import AppIntents

/// Opens the app on the Log tab: what the lock-screen control runs.
///
/// Lives in Shared for the same reason as `SameAgainIntent`: the control in the
/// extension names it, the app's process performs it. The app installs
/// `handler` at launch to pick the tab; in the extension it stays nil.
nonisolated struct OpenLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Grepp"
    static var description = IntentDescription("Opens Grepp on the Log tab.")
    static var openAppWhenRun = true

    @MainActor static var handler: (() -> Void)?

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { Self.handler?() }
        return .result()
    }
}
