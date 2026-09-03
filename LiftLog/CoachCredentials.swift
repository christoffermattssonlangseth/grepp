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
/// 3. **`Secrets.plist`** — an untracked file in `LiftLog/` with a single
///    `ANTHROPIC_API_KEY` string. Gitignored, but note it *is* copied into the
///    app bundle, so treat it as dev-only convenience: a key in a bundle is
///    extractable from the binary exactly like a hardcoded one.
///
/// All three are development-grade: a key that reaches the app can be pulled back
/// out of the binary. Before this app goes to anyone else, put a backend in front
/// that holds the key server-side and forwards requests, and point
/// `ClaudeService` at it instead of `api.anthropic.com`.
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

        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let key = plist["ANTHROPIC_API_KEY"] as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    static var hasKey: Bool { resolve() != nil }
}
