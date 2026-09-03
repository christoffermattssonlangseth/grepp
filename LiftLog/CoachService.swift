import Foundation
import Combine

/// Which Claude answers. Sonnet is the default — fast and cheap enough to ask
/// "heavy or light today?" between sets; Opus is there when you want it to
/// actually chew on a few months of history.
enum CoachModelChoice: String, CaseIterable, Identifiable, Codable {
    case sonnet, opus

    var id: String { rawValue }

    /// The API model ID. Dateless IDs are pinned snapshots, not evergreen
    /// pointers — never append a date suffix.
    var apiID: String {
        switch self {
        case .sonnet: return "claude-sonnet-5"
        case .opus: return "claude-opus-5"
        }
    }

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

/// Drives one Coach conversation: holds the transcript, rebuilds the training
/// context each turn, and streams the answer back into `messages`.
///
/// Nothing here logs the prompt, the training log or the key. The log is built in
/// exactly one place — `CoachContext.systemPrompt` — and goes straight into the
/// request from there.
@MainActor
final class CoachService: ObservableObject {
    @Published private(set) var messages: [CoachMessage] = []
    @Published private(set) var isResponding = false
    @Published private(set) var errorText: String?
    /// What the model was actually shown, for the header ("42 sessions 2026-01-04 → 2026-09-01").
    @Published private(set) var contextNote: String?

    /// What this conversation is doing. Set when an interview starts and kept for
    /// the rest of the chat, so follow-up turns still know the protocol.
    @Published private(set) var mode: CoachContext.Mode = .coaching

    private var task: Task<Void, Never>?

    var isEmpty: Bool { messages.isEmpty }

    /// A finished goals file the coach has offered, once it has stopped streaming.
    var proposedGoals: String? {
        guard !isResponding, let last = messages.last, last.role == .coach else { return nil }
        return CoachContext.parseReply(last.text).goals
    }

    /// Begin the goals interview: the coach leads from here.
    func startGoalsInterview(model: CoachModelChoice,
                             sessions: [Session],
                             brief: CoachContext.Brief,
                             workspace: String) {
        reset()
        mode = .goalsInterview
        send(CoachContext.goalsInterviewRequest,
             model: model, sessions: sessions, brief: brief, workspace: workspace)
    }

    /// Start over. The next question rebuilds the log context from scratch.
    func reset() {
        task?.cancel()
        task = nil
        messages = []
        errorText = nil
        contextNote = nil
        isResponding = false
        mode = .coaching
    }

    /// Stop the answer in flight, keeping whatever streamed in so far.
    func cancel() {
        task?.cancel()
        task = nil
        finishStreamingMessage()
        isResponding = false
    }

    func send(_ question: String,
              model: CoachModelChoice,
              sessions: [Session],
              brief: CoachContext.Brief,
              workspace: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        errorText = nil

        guard let key = CoachCredentials.resolve() else {
            messages.append(CoachMessage(role: .you, text: trimmed))
            errorText = ClaudeService.ClaudeError.missingKey.localizedDescription
            return
        }

        // Every turn carries the whole conversation, so follow-ups have the thread.
        var turns = messages.map {
            ClaudeService.Turn(role: $0.role == .you ? .user : .assistant, text: $0.text)
        }
        turns.append(ClaudeService.Turn(role: .user, text: trimmed))

        // Rebuilt per question rather than pinned at the start of the chat, so a
        // workout logged mid-conversation is picked up on the next answer.
        let excerpt = CoachContext.excerpt(from: sessions)
        let system = CoachContext.systemPrompt(for: excerpt, brief: brief, mode: mode)
        // Say when the standing brief is in play — otherwise there's no way to
        // tell from the answers whether the coaching notes were picked up.
        contextNote = brief.hasContent ? excerpt.note + " + your brief" : excerpt.note

        messages.append(CoachMessage(role: .you, text: trimmed))
        let reply = CoachMessage(role: .coach, text: "", isStreaming: true)
        messages.append(reply)
        isResponding = true

        let service = ClaudeService(apiKey: key, model: model, workspaceID: workspace)

        task = Task { [weak self] in
            do {
                for try await chunk in service.stream(system: system, turns: turns) {
                    guard let self, !Task.isCancelled else { return }
                    self.append(chunk, to: reply.id)
                }
            } catch is CancellationError {
                // Left the partial answer in place on purpose.
            } catch {
                // Surface the failure, not the request: ClaudeError carries the
                // status and the API's reason — never the prompt or the log.
                self?.errorText = error.localizedDescription
            }
            guard let self else { return }
            self.finishStreamingMessage()
            self.isResponding = false
            self.task = nil
        }
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += chunk
    }

    private func finishStreamingMessage() {
        guard let idx = messages.lastIndex(where: { $0.isStreaming }) else { return }
        messages[idx].isStreaming = false
        // A request that failed before a single token arrived leaves an empty
        // bubble behind; drop it and let `errorText` do the talking.
        if messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        }
    }
}
