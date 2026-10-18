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
        // Readable once the phone has been unlocked since boot — not only
        // while it's unlocked now: the lock-screen button can launch the app
        // with the screen locked, and that launch must still see the token.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Update in place, and add only when there's nothing there. Never
        // delete first: an add that then fails would lose the secret.
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attributes) { $1 }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        assert(status == errSecSuccess || status == errSecInteractionNotAllowed, "Keychain write failed: \(status)")
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
