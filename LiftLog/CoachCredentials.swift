import Foundation

/// Where the Claude API key comes from. Never a literal in source, and never
/// anything that lands in git — this repo is public.
///
/// Resolution order, first hit wins:
///
/// 1. **Keychain** — pasted into Settings ▸ Coach. The normal path, and the only
///    one that survives on a real device.
/// 2. **`ANTHROPIC_API_KEY` environment variable** — set it in the Xcode scheme
///    (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments ▸ Environment Variables),
///    which is stored in `xcuserdata/` and already gitignored. Handy in the
///    Simulator; it does not exist for an app launched from the home screen.
///
/// Nothing is read from the app bundle: a file in a bundle is readable by anyone
/// with the binary, so `Secrets.plist` is kept out of the build on purpose
/// (an exception in the project), and a shipped build has only the Keychain.
/// Every lifter brings their own key; the developer never holds one.
enum CoachCredentials {
    static let account = "anthropic_api_key"

    /// The key stored in the Keychain, if the user has entered one.
    static var stored: String? {
        Keychain.get(account: account, service: Keychain.anthropicService)
    }

    /// Save (or clear, when empty) the key in the Keychain.
    static func store(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(account: account, service: Keychain.anthropicService)
        } else {
            Keychain.set(trimmed, account: account, service: Keychain.anthropicService)
        }
    }

    /// The key to authenticate with, from whichever source has one.
    ///
    /// Deliberately returns the key and nothing else — no logging, no telling the
    /// caller which source won, since a message like "using the key from X" is one
    /// refactor away from printing the key itself.
    static func resolve() -> String? {
        if let stored, !stored.isEmpty { return stored }

        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }


        return nil
    }

    static var hasKey: Bool { resolve() != nil }
}
