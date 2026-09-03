import Foundation
import Combine

#if canImport(ClaudeForFoundationModels)
import FoundationModels
import ClaudeForFoundationModels
#endif

/// Which Claude answers. Sonnet is the default — fast and cheap enough to ask
/// "heavy or light today?" between sets; Opus is there when you want it to
/// actually chew on a few months of history.
enum CoachModelChoice: String, CaseIterable, Identifiable, Codable {
    case sonnet, opus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sonnet: return "Sonnet 5"
        case .opus: return "Opus 5"
        }
    }

    var blurb: String {
        switch self {
        case .sonnet: return "Fast and cheap — the everyday default."
        case .opus: return "Slower and pricier; better at deep analysis."
        }
    }
}

/// One turn in the Coach conversation.
struct CoachMessage: Identifiable, Equatable {
    enum Role { case you, coach }

    let id = UUID()
    let role: Role
    var text: String
    var isStreaming = false
}

/// Why the Coach tab can't talk to Claude right now.
enum CoachError: LocalizedError {
    case packageMissing
    case unsupportedOS
    case missingKey

    var errorDescription: String? {
        switch self {
        case .packageMissing:
            return "This build doesn't include the ClaudeForFoundationModels package. Add it in Xcode 27 (see README ▸ Coach)."
        case .unsupportedOS:
            return "Coach needs iOS 27 or later — that's the release whose Foundation Models framework can talk to a server-side model."
        case .missingKey:
            return "No Claude API key. Add one in Settings ▸ Coach."
        }
    }
}

/// What the Coach tab can do in this build, on this device, right now.
enum CoachAvailability: Equatable {
    case ready
    case needsKey
    case needsOS
    case needsPackage

    static var current: CoachAvailability {
        #if canImport(ClaudeForFoundationModels)
        guard #available(iOS 27.0, macOS 27.0, *) else { return .needsOS }
        return CoachCredentials.hasKey ? .ready : .needsKey
        #else
        return .needsPackage
        #endif
    }
}

/// The one thing the view needs from a model: stream an answer to a question.
///
/// Behind a protocol so the whole `FoundationModels` surface stays inside a
/// single `#if canImport` block — the app compiles, and the Coach tab explains
/// itself, on a toolchain that doesn't have the package yet.
@MainActor
protocol CoachBackend {
    /// Each element is the answer *so far*, not a delta.
    func stream(_ question: String) -> AsyncThrowingStream<String, Error>
}

#if canImport(ClaudeForFoundationModels)

/// Claude driven through Apple's `LanguageModelSession`, which the
/// `ClaudeForFoundationModels` package conforms Claude to.
@available(iOS 27.0, macOS 27.0, *)
@MainActor
struct ClaudeCoachBackend: CoachBackend {
    private let session: LanguageModelSession

    init(model: CoachModelChoice, apiKey: String, instructions: String) {
        // `.apiKey` is development-grade: a key that reaches the app is a key that
        // can be pulled back out of it. Before distributing this to anyone else,
        // switch to `.appAttest(clientID: "clid_…")` — Anthropic's recommended path,
        // which ships no key at all — or `.proxied(...)` through your own backend.
        let claude = ClaudeLanguageModel(
            name: model.claudeModel,
            auth: .apiKey(apiKey)
        )
        // Instructions carry the coach's brief *and* the training log, so history is
        // sent once per conversation and every follow-up question can lean on it.
        session = LanguageModelSession(model: claude) { instructions }
    }

    func stream(_ question: String) -> AsyncThrowingStream<String, Error> {
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    for try await partial in session.streamResponse(to: question) {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@available(iOS 27.0, macOS 27.0, *)
private extension CoachModelChoice {
    /// The package's constants mirror the API model IDs (`.opus5` is `claude-opus-5`)
    /// and carry each model's capabilities, so don't hand-roll a `ClaudeModel` here.
    var claudeModel: ClaudeModel {
        switch self {
        case .sonnet: return .sonnet5
        case .opus: return .opus5
        }
    }
}

#endif

/// Drives one Coach conversation: holds the transcript, starts a session against
/// the chosen model, and streams answers back into `messages`.
///
/// Nothing here logs the prompt, the training log or the key. The log reaches
/// exactly one place — `CoachContext.instructions` — and goes straight to the
/// session from there.
@MainActor
final class CoachService: ObservableObject {
    @Published private(set) var messages: [CoachMessage] = []
    @Published private(set) var isResponding = false
    @Published private(set) var errorText: String?
    /// What the model was actually shown, for the header ("42 sessions 2026-01-04 → 2026-09-01").
    @Published private(set) var contextNote: String?

    private var backend: (any CoachBackend)?
    private var backendModel: CoachModelChoice?
    private var task: Task<Void, Never>?

    var isEmpty: Bool { messages.isEmpty }

    /// Drop the conversation and its session. The next question re-reads the log,
    /// so this is also how you pick up a workout logged since the chat started.
    func reset() {
        task?.cancel()
        task = nil
        messages = []
        backend = nil
        backendModel = nil
        errorText = nil
        contextNote = nil
        isResponding = false
    }

    /// Stop the answer in flight, keeping whatever streamed in so far.
    func cancel() {
        task?.cancel()
        task = nil
        finishStreamingMessage()
        isResponding = false
    }

    func send(_ question: String, model: CoachModelChoice, sessions: [Session]) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        errorText = nil
        messages.append(CoachMessage(role: .you, text: trimmed))

        let backend: any CoachBackend
        do {
            backend = try makeBackend(for: model, sessions: sessions)
        } catch {
            errorText = error.localizedDescription
            return
        }

        let reply = CoachMessage(role: .coach, text: "", isStreaming: true)
        messages.append(reply)
        isResponding = true

        task = Task { [weak self] in
            do {
                for try await text in backend.stream(trimmed) {
                    guard let self, !Task.isCancelled else { return }
                    self.update(reply.id, text: text)
                }
            } catch is CancellationError {
                // Left the partial answer in place on purpose.
            } catch {
                // Surface the failure, not the request: the package maps API errors
                // to `LanguageModelError` / `ClaudeError`, whose descriptions carry
                // status and reason — never the prompt or the log.
                self?.errorText = error.localizedDescription
            }
            guard let self else { return }
            self.finishStreamingMessage()
            self.isResponding = false
            self.task = nil
        }
    }

    /// Reuse the running session while the model is unchanged, so follow-ups keep
    /// the thread. Switching model starts a fresh one — a `LanguageModelSession` is
    /// bound to the model it was created with.
    private func makeBackend(for model: CoachModelChoice, sessions: [Session]) throws -> any CoachBackend {
        if let backend, backendModel == model { return backend }

        #if canImport(ClaudeForFoundationModels)
        guard #available(iOS 27.0, macOS 27.0, *) else { throw CoachError.unsupportedOS }
        guard let key = CoachCredentials.resolve() else { throw CoachError.missingKey }

        let excerpt = CoachContext.excerpt(from: sessions)
        let made = ClaudeCoachBackend(
            model: model,
            apiKey: key,
            instructions: CoachContext.instructions(for: excerpt)
        )
        backend = made
        backendModel = model
        contextNote = excerpt.note
        return made
        #else
        throw CoachError.packageMissing
        #endif
    }

    private func update(_ id: UUID, text: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text = text
    }

    private func finishStreamingMessage() {
        guard let idx = messages.lastIndex(where: { $0.isStreaming }) else { return }
        messages[idx].isStreaming = false
        // An answer that failed before a single token arrived leaves an empty
        // bubble behind; drop it and let `errorText` do the talking.
        if messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        }
    }
}
