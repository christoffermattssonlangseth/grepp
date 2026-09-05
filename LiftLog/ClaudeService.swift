import Foundation

/// Talks to the Claude Messages API over plain HTTPS, streaming the reply.
///
/// Same shape as `GitHubService`: a value type holding the config, `URLSession`
/// for transport, and one typed error. There is no official Anthropic Swift SDK,
/// so this is raw HTTP against the documented wire format.
struct ClaudeService {
    var apiKey: String
    var model: CoachModelChoice
    /// Workspace to bill and act in. Required for a key that isn't scoped to a
    /// single workspace (a "personal" or "service account" key spanning several);
    /// empty, and the header is left off, which is what a workspace-scoped key wants.
    var workspaceID: String = ""

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// The Messages API wire version this code is written against. Anthropic
    /// versions the format by date, so bump it only alongside a matching change
    /// to the request and event shapes below.
    private static let apiVersion = "2023-06-01"

    /// Ceiling on one reply, not a target — hitting it truncates mid-sentence, so
    /// it's set generously. Thinking tokens count against it too. What actually
    /// keeps answers short is the "read on a phone" line in the system prompt.
    private static let maxTokens = 16_000

    /// Token counts the API reports for one answer. Input is split three ways
    /// because they bill differently: fresh, read from the prompt cache, and
    /// written to it.
    struct Usage: Equatable, Codable {
        var input = 0
        var cacheRead = 0
        var cacheWrite = 0
        var output = 0
    }

    /// What the stream yields: text as it arrives, and usage as the API reports it.
    enum Event {
        case text(String)
        case usage(Usage)
    }

    /// One turn of the conversation as the API wants it.
    struct Turn: Equatable {
        enum Role: String { case user, assistant }
        var role: Role
        var text: String
    }

    enum ClaudeError: LocalizedError {
        case missingKey
        case missingWorkspace
        case notHTTP
        case api(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "No Claude API key. Add one in Settings ▸ Coach."
            case .missingWorkspace:
                return "This key isn't tied to one workspace, so Claude needs to be told which to use. Paste the workspace ID in Settings ▸ Coach — it's the ID column of Settings ▸ Workspaces in the Claude Console."
            case .notHTTP:
                return "Unexpected non-HTTP response from the Claude API."
            case .api(let status, let message):
                switch status {
                case 401, 403:
                    return "Claude rejected the API key. Check it in Settings ▸ Coach."
                case 404 where message.localizedCaseInsensitiveContains("workspace"):
                    return "Claude doesn't recognise that workspace ID, or this key can't reach it. Check it in Settings ▸ Coach."
                case 429:
                    return "Rate limited by Claude — wait a moment and ask again."
                case 500...599:
                    return "Claude is having trouble (\(status)). Try again shortly."
                default:
                    return message.isEmpty ? "Claude \(status)." : "Claude \(status): \(message)"
                }
            }
        }
    }

    /// Stream one answer. Text arrives as **chunks** of new text, not the whole
    /// answer so far — the caller appends. Usage arrives as the API reports it:
    /// input counts at the start, the output count at the end.
    func stream(system: String, turns: [Turn]) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await send(system: system, turns: turns) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func send(system: String, turns: [Turn], onEvent: (Event) -> Void) async throws {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Only sent when set: a workspace-scoped key rejects nothing, but an empty
        // header value is not a valid workspace ID.
        let workspace = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workspace.isEmpty {
            request.setValue(workspace, forHTTPHeaderField: "anthropic-workspace-id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body(system: system, turns: turns))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.notHTTP }

        guard (200..<300).contains(http.statusCode) else {
            // A rejected request answers with a plain JSON error body rather than a
            // stream, but it still arrives as bytes — reassemble it to get the reason.
            var raw = ""
            for try await line in bytes.lines { raw += line }
            let reason = Self.reason(fromErrorBody: raw)
            // The API names this one precisely; turn it into an instruction the user
            // can act on rather than passing the raw wording through.
            if http.statusCode == 400, reason.contains("anthropic-workspace-id") {
                throw ClaudeError.missingWorkspace
            }
            throw ClaudeError.api(status: http.statusCode, message: reason)
        }

        // Server-sent events: "event:" lines name the type, "data:" lines carry the
        // JSON, blank lines separate them. The JSON has its own "type", so the
        // "event:" lines are redundant here and skipped.
        var usage = Usage()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_delta":
                // Only text_delta is the answer. Both models run adaptive thinking by
                // default, whose blocks stream separately — deliberately not shown.
                guard let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String else { continue }
                onEvent(.text(text))
            case "message_start":
                // Input-side counts come with the opening event.
                if let u = (event["message"] as? [String: Any])?["usage"] as? [String: Any] {
                    usage.input = u["input_tokens"] as? Int ?? 0
                    usage.cacheRead = u["cache_read_input_tokens"] as? Int ?? 0
                    usage.cacheWrite = u["cache_creation_input_tokens"] as? Int ?? 0
                    onEvent(.usage(usage))
                }
            case "message_delta":
                // The output count arrives with the closing one, cumulative.
                if let u = event["usage"] as? [String: Any], let out = u["output_tokens"] as? Int {
                    usage.output = out
                    onEvent(.usage(usage))
                }
            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String
                throw ClaudeError.api(status: http.statusCode, message: message ?? "")
            default:
                continue
            }
        }
    }

    private func body(system: String, turns: [Turn]) -> [String: Any] {
        [
            "model": model.apiID,
            "max_tokens": Self.maxTokens,
            "stream": true,
            // The system prompt is an array of blocks so the training log can carry
            // cache_control: it's byte-identical across every turn of a conversation,
            // so caching makes follow-up questions markedly cheaper. A log shorter
            // than the model's minimum cacheable prefix simply isn't cached — no
            // error, no benefit.
            "system": [[
                "type": "text",
                "text": system,
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": Self.alternating(turns).map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
    }

    /// The API requires roles to strictly alternate. They normally do, but a
    /// question that fails before any text arrives leaves no assistant turn behind,
    /// so the next question would send two `user` turns and earn a 400. Fold any
    /// run of same-role turns into one rather than dropping the user's words.
    static func alternating(_ turns: [Turn]) -> [Turn] {
        turns.reduce(into: [Turn]()) { result, turn in
            if result.last?.role == turn.role {
                result[result.count - 1].text += "\n\n" + turn.text
            } else {
                result.append(turn)
            }
        }
    }

    /// Pull `error.message` out of an error body, if it's shaped as documented.
    private static func reason(fromErrorBody raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else { return "" }
        return message
    }
}
