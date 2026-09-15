import Foundation
import Security

/// Minimal Keychain wrapper for storing secrets securely (never in
/// UserDefaults / @AppStorage, and never in source). Callers pass a `service`
/// to keep unrelated credentials — the GitHub token, the Claude API key — in
/// separate keychain items.
enum Keychain {
    static let gitHubService = "com.liftlog.github"
    static let anthropicService = "com.liftlog.anthropic"

    static func set(_ value: String, account: String, service: String = gitHubService) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        // Readable once the phone has been unlocked since boot — not only
        // while it's unlocked now: the lock-screen button can launch the app
        // with the screen locked, and that launch must still see the token.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        assert(status == errSecSuccess || status == errSecInteractionNotAllowed, "Keychain add failed: \(status)")
    }

    static func get(account: String, service: String = gitHubService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String, service: String = gitHubService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
