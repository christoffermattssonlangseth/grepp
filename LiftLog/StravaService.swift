import AuthenticationServices
import Combine
import Foundation
import UIKit

/// Strava, for posting a session. OAuth once, tokens in the Keychain,
/// refreshed when they lapse; then one call to create an activity and one
/// to update it if the session grows after posting.
///
/// The client ID and secret come from `Secrets.plist` (untracked; this repo
/// is public) or the environment, never from source. Strava's token exchange
/// needs the secret on the client, which is what their mobile guidance does
/// too — treat it as the dev-grade arrangement it is.
@MainActor
final class StravaService: ObservableObject {
    static let shared = StravaService()

    /// The connected athlete's name, or nil when not connected.
    @Published private(set) var athlete: String?
    @Published private(set) var isBusy = false
    /// A client ID and secret are on hand, from wherever.
    @Published private(set) var isConfigured = false

    private static let service = "com.liftlog.strava"
    private static let redirect = "grepp://localhost/strava"
    private static let scope = "activity:write"

    struct Tokens: Codable {
        var access: String
        var refresh: String
        var expiresAt: Date
        var athlete: String
    }

    enum StravaError: LocalizedError {
        case notConfigured, notConnected, cancelled, api(status: Int, message: String)
        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Strava isn't set up: paste your API app's client ID and secret in Settings ▸ Strava."
            case .notConnected: return "Connect Strava in Settings first."
            case .cancelled: return "Strava sign-in was cancelled."
            case .api(let status, let message):
                switch status {
                case 401: return "Strava rejected the connection — reconnect in Settings."
                case 409: return "Strava already has an activity at that time."
                case 429: return "Strava's rate limit — try again in a few minutes."
                default: return message.isEmpty ? "Strava \(status)." : "Strava \(status): \(message)"
                }
            }
        }
    }

    init() {
        athlete = tokens?.athlete
        isConfigured = Self.secret("STRAVA_CLIENT_ID") != nil && Self.secret("STRAVA_CLIENT_SECRET") != nil
    }

    var isConnected: Bool { tokens != nil }

    // MARK: - Configuration

    /// The API app's ID and secret, pasted in Settings. Keychain, like the
    /// Claude key; the environment and Secrets.plist are the dev-time fallbacks.
    func storeCredentials(id: String, secret: String) {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { Keychain.delete(account: "client_id", service: Self.service) }
        else { Keychain.set(id, account: "client_id", service: Self.service) }
        if secret.isEmpty { Keychain.delete(account: "client_secret", service: Self.service) }
        else { Keychain.set(secret, account: "client_secret", service: Self.service) }
        isConfigured = Self.secret("STRAVA_CLIENT_ID") != nil && Self.secret("STRAVA_CLIENT_SECRET") != nil
    }

    private static func secret(_ key: String) -> String? {
        let account = key == "STRAVA_CLIENT_ID" ? "client_id" : "client_secret"
        if let kept = Keychain.get(account: account, service: service), !kept.isEmpty { return kept }
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty { return env }
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Tokens

    private var tokens: Tokens? {
        get {
            guard let raw = Keychain.get(account: "tokens", service: Self.service),
                  let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Tokens.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue),
               let raw = String(data: data, encoding: .utf8) {
                Keychain.set(raw, account: "tokens", service: Self.service)
            } else {
                Keychain.delete(account: "tokens", service: Self.service)
            }
            athlete = newValue?.athlete
        }
    }

    func disconnect() { tokens = nil }

    // MARK: - OAuth

    /// Open Strava's consent page in a sheet and trade the code for tokens.
    func connect() async throws {
        guard let id = Self.secret("STRAVA_CLIENT_ID"), Self.secret("STRAVA_CLIENT_SECRET") != nil else {
            throw StravaError.notConfigured
        }
        var parts = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        parts.queryItems = [
            .init(name: "client_id", value: id),
            .init(name: "redirect_uri", value: Self.redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: Self.scope),
        ]
        let callback = try await WebAuth.run(url: parts.url!, scheme: "grepp")
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StravaError.cancelled
        }
        isBusy = true
        defer { isBusy = false }
        tokens = try await exchange(["grant_type": "authorization_code", "code": code])
    }

    /// A valid access token, refreshed first if it has lapsed.
    private func accessToken() async throws -> String {
        guard let current = tokens else { throw StravaError.notConnected }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.access }
        var refreshed = try await exchange(["grant_type": "refresh_token", "refresh_token": current.refresh])
        refreshed.athlete = current.athlete   // a refresh doesn't return the athlete
        tokens = refreshed
        return refreshed.access
    }

    private func exchange(_ params: [String: String]) async throws -> Tokens {
        guard let id = Self.secret("STRAVA_CLIENT_ID"), let secret = Self.secret("STRAVA_CLIENT_SECRET") else {
            throw StravaError.notConfigured
        }
        var all = params
        all["client_id"] = id
        all["client_secret"] = secret
        let json = try await call("POST", URL(string: "https://www.strava.com/oauth/token")!, form: all, token: nil)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expires = json["expires_at"] as? Double else {
            throw StravaError.api(status: 0, message: "unexpected token response")
        }
        let who = json["athlete"] as? [String: Any]
        let name = [who?["firstname"] as? String, who?["lastname"] as? String]
            .compactMap { $0 }.joined(separator: " ")
        return Tokens(access: access, refresh: refresh,
                      expiresAt: Date(timeIntervalSince1970: expires), athlete: name)
    }

    // MARK: - Activities

    /// Create the activity; returns Strava's id for it.
    func post(name: String, description: String, start: Date, elapsed: TimeInterval) async throws -> Int {
        isBusy = true
        defer { isBusy = false }
        let token = try await accessToken()
        let json = try await call("POST", URL(string: "https://www.strava.com/api/v3/activities")!, form: [
            "name": name,
            "sport_type": StravaPost.sportType,
            "start_date_local": Self.iso(start),
            "elapsed_time": String(Int(elapsed)),
            "description": description,
        ], token: token)
        guard let id = json["id"] as? Int ?? (json["id"] as? Double).map(Int.init) else {
            throw StravaError.api(status: 0, message: "no activity id in reply")
        }
        return id
    }

    /// The session grew after posting: update what's there rather than post twice.
    func update(id: Int, name: String, description: String) async throws {
        isBusy = true
        defer { isBusy = false }
        let token = try await accessToken()
        _ = try await call("PUT", URL(string: "https://www.strava.com/api/v3/activities/\(id)")!,
                           form: ["name": name, "description": description], token: token)
    }

    // MARK: - HTTP

    private func call(_ method: String, _ url: URL, form: [String: String], token: String?) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // A form body escapes "+" as a space unless it's encoded as %2B.
        request.httpBody = body.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StravaError.api(status: 0, message: "not HTTP") }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let message = json["message"] as? String ?? ""
            throw StravaError.api(status: http.statusCode, message: message)
        }
        return json
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f.string(from: date)
    }
}

/// The system sign-in sheet, wrapped for async/await.
private enum WebAuth {
    @MainActor
    static func run(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: StravaService.StravaError.cancelled) }
            }
            session.presentationContextProvider = Anchor.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    /// Where the sheet is presented from: the key window.
    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = Anchor()
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let key = scenes.compactMap(\.keyWindow).first { return key }
            // The sheet is only ever asked for from a button on screen, so a
            // window exists; without one there is nothing to present from anyway.
            guard let window = scenes.flatMap(\.windows).first else {
                preconditionFailure("Strava sign-in needs a window")
            }
            return window
        }
    }
}
