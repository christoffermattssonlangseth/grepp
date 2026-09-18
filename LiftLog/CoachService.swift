import Foundation
import Combine

/// Which Claude answers. Sonnet is the default — fast and cheap enough to ask
/// "heavy or light today?" between sets; Opus is there when you want it to
/// actually chew on a few months of history.
enum CoachModelChoice: String, CaseIterable, Identifiable, Codable {
    case sonnet, opus
    /// Anthropic's most capable model: twice Opus per token and slower. For the
    /// question you would pay a coach for, behind a cap and a first-time ask.
    case fable
    /// Apple's model, on the phone. Free and private; small.
    case onDevice

    var id: String { rawValue }

    var isOnDevice: Bool { self == .onDevice }

    /// The choices this phone can offer: the on-device one only where the
    /// framework exists and the hardware can run it.
    @MainActor static var offered: [CoachModelChoice] {
        allCases.filter { !$0.isOnDevice || AppleCoach.isSupported }
    }

    /// The API model ID. Dateless IDs are pinned snapshots, not evergreen
    /// pointers — never append a date suffix.
    var apiID: String {
        switch self {
        case .sonnet: return "claude-sonnet-5"
        case .opus: return "claude-opus-5"
        case .fable: return "claude-fable-5-1"
        case .onDevice: return ""   // never sent anywhere
        }
    }

    var label: String {
        switch self {
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        case .fable: return "Fable"
        case .onDevice: return "On device"
        }
    }

    /// The one that asks before it's used, and costs the most when it is.
    var isPremium: Bool { self == .fable }

    /// How hard the model thinks. Fable reasons at length by default and a
    /// coach question is routine work, so it runs at medium; the others are
    /// left at the platform's default.
    var effort: String? { self == .fable ? "medium" : nil }

    /// Dollars per million tokens, input and output. Cache writes bill at a
    /// quarter more than input on every model; cache reads at a tenth of input,
    /// except on Fable where they're a fortieth. Check
    /// https://platform.claude.com/docs/en/about-claude/pricing if in doubt;
    /// the app only ever shows the result with a tilde.
    var rates: (input: Double, output: Double) {
        switch self {
        case .sonnet: return (2.0, 10.0)
        case .opus: return (5.0, 25.0)
        case .fable: return (10.0, 50.0)
        case .onDevice: return (0, 0)
        }
    }

    var cacheReadShare: Double { self == .fable ? 0.025 : 0.1 }

    func cost(_ u: ClaudeService.Usage) -> Double {
        let m = 1.0 / 1_000_000
        return Double(u.input) * rates.input * m
             + Double(u.cacheRead) * rates.input * cacheReadShare * m
             + Double(u.cacheWrite) * rates.input * 1.25 * m
             + Double(u.output) * rates.output * m
             + Double(u.searches ?? 0) * 0.01   // $10 per thousand searches, any model
    }

    var blurb: String {
        switch self {
        case .sonnet: return "Fast and cheap — the everyday default."
        case .opus: return "Slower and pricier; better at deep analysis."
        case .fable: return "The most capable, at twice Opus and slower. For the question you'd pay a coach for."
        case .onDevice: return "Apple's model on the phone. Free, private, small: it sees your last few weeks, not the whole log."
        }
    }
}

/// One turn in the Coach conversation.
struct CoachMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case you, coach }

    var id = UUID()
    let role: Role
    var text: String
    var isStreaming = false
    /// What the answer cost, once the API has said. Coach replies only.
    var usage: ClaudeService.Usage?
    var model: CoachModelChoice?
    /// This answer went and read the paper: searched, fetched, cited.
    var isLookup: Bool?
    /// Why the answer ended when it wasn't finished: "refusal", "max_tokens",
    /// "pause_turn". Shown under the bubble, never sent back as Claude's words.
    var stop: String?

    /// The sentence for `stop`, in the app's voice.
    var stopNote: String? {
        switch stop {
        case "refusal": return "Claude declined this one: its safety filter stopped the answer. Rephrase it, or ask another model."
        case "max_tokens": return "The answer hit the length limit and was cut off here."
        case "pause_turn": return "The search ran out of rounds before it finished. Ask again to continue."
        default: return nil
        }
    }
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
    /// Which send owns the screen. A stopped request still unwinds after the
    /// next one has started; its tail must not touch the new reply.
    private var turn: UUID?
    /// Replies whose cost has gone to the month, so a stop and a finish on the
    /// same reply can't count it twice.
    private var recorded = Set<UUID>()

    // The transcript is persisted so a backgrounded-and-killed app doesn't lose
    // the conversation. Saved when a message lands or finishes, never per
    // streamed chunk.
    private let chatKey = "coach_chat"
    private let seenKey = "coach_seen_log"

    /// The log lines as they stood at the last send, so the next send can say
    /// what's new. Kept across launches with the chat; cleared with it.
    private var seenLines: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: seenKey) }
    }
    private struct Saved: Codable {
        var messages: [CoachMessage]
        var mode: CoachContext.Mode
        var contextNote: String?
    }

    init() { restore() }

    private func persist() {
        let saved = Saved(messages: messages, mode: mode, contextNote: contextNote)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: chatKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: chatKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        // A reply cut off by a kill is kept as it stood, like a cancel — and an
        // empty bubble the kill left behind is dropped. What it cost was billed
        // all the same, so it goes to the month here.
        for m in saved.messages where m.isStreaming {
            if let usage = m.usage, let model = m.model { CoachSpend.shared.record(model.cost(usage)) }
        }
        messages = saved.messages
            .map { var m = $0; m.isStreaming = false; return m }
            .filter { !($0.role == .coach && $0.stop == nil && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        mode = saved.mode
        contextNote = saved.contextNote
    }

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
                             muscleMap: MuscleMap,
                             workspace: String) {
        // The checks `send` makes, made first: an interview that can't start
        // must not have wiped the chat and left the mode switched.
        errorText = nil
        if model.isOnDevice {
            errorText = "The goals interview needs Claude. Pick Sonnet, Opus or Fable for it."
            return
        }
        if let stop = CoachSpend.shared.block() { errorText = stop; return }
        guard CoachCredentials.resolve() != nil else {
            errorText = ClaudeService.ClaudeError.missingKey.localizedDescription
            return
        }
        reset()
        mode = .goalsInterview
        send(CoachContext.goalsInterviewRequest,
             model: model, sessions: sessions, brief: brief, muscleMap: muscleMap, workspace: workspace)
    }

    /// Start over. The next question rebuilds the log context from scratch.
    func reset() {
        task?.cancel()
        task = nil
        messages = []
        seenLines = []
        errorText = nil
        contextNote = nil
        isResponding = false
        mode = .coaching
        persist()
    }

    /// Stop the answer in flight, keeping whatever streamed in so far.
    func cancel() {
        task?.cancel()
        task = nil
        turn = nil
        finishStreamingMessage()
        isResponding = false
        persist()
    }

    func send(_ question: String,
              model: CoachModelChoice,
              sessions: [Session],
              brief: CoachContext.Brief,
              draft: SessionDraft? = nil,
              plans: [PlanRecord] = [],
              muscleMap: MuscleMap,
              workspace: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        errorText = nil

        if model.isOnDevice {
            sendOnDevice(trimmed, sessions: sessions, brief: brief, draft: draft, muscleMap: muscleMap)
            return
        }

        // The monthly cap: judged before the request, against what every
        // answer so far was estimated to cost.
        if let stop = CoachSpend.shared.block() {
            messages.append(CoachMessage(role: .you, text: trimmed))
            errorText = stop
            return
        }

        guard let key = CoachCredentials.resolve() else {
            messages.append(CoachMessage(role: .you, text: trimmed))
            errorText = ClaudeService.ClaudeError.missingKey.localizedDescription
            return
        }

        // Every turn carries the whole conversation, so follow-ups have the thread.
        var turns = messages.map {
            ClaudeService.Turn(role: $0.role == .you ? .user : .assistant, text: $0.text)
        }
        // A paper to look up: the DOI goes in as a link, because the fetch tool
        // may only follow what the lifter's own message contains.
        let lookup = mode == .coaching ? CoachContext.lookupTarget(in: trimmed) : nil
        var sent = trimmed
        if let url = lookup?.url, !trimmed.contains(url) { sent += "\n\n(Paper: \(url))" }
        turns.append(ClaudeService.Turn(role: .user, text: sent))

        // Rebuilt per question rather than pinned at the start of the chat, so a
        // workout logged mid-conversation is picked up on the next answer.
        let excerpt = CoachContext.excerpt(from: sessions)
        // The digest carries the same dose reading Trends shows, for lifts done
        // in the last eight weeks: the tab and the chat then agree on a stall.
        let eightWeeksAgo = Date().addingTimeInterval(-56 * 86_400)
        var digest: String?
        if mode == .coaching {
            digest = CoachContext.liftDigest(from: sessions, dose: { row in
                guard row.last >= eightWeeksAgo,
                      let dose = DoseResponse.make(for: row.name, in: sessions, map: muscleMap),
                      dose.verdict != .tooEarly else { return nil }
                return dose.summary
            })
        }
        let system = CoachContext.systemPrompt(for: excerpt, brief: brief, mode: mode, digest: digest)
        // What entered the log since the last answer in this chat — lines the
        // model has not been told about, whatever it said before them.
        let lines = Set(WorkoutParser.serialize(sessions).split(separator: "\n").map(String.init).filter { !$0.isEmpty })
        // Nothing to compare against on a fresh chat, or one that predates
        // this note: reporting the whole log as "new" would be noise.
        let newLines = (messages.isEmpty || seenLines.isEmpty) ? [] : lines.subtracting(seenLines).sorted()
        // Committed only once an answer has arrived: a failed request must
        // not count as the model having been told.
        let seenAfterReply = lines
        // The lift in the lifter's hands right now, which the log doesn't have
        // yet, and how recent prescriptions went. Sent as its own uncached block
        // so the log's cache holds.
        var live = mode == .coaching
            ? CoachContext.liveNote(draft: draft, plans: plans,
                                    weeklySets: muscleMap.weeklySets(weeks: 4, in: sessions),
                                    unmapped: muscleMap.unmapped(in: sessions),
                                    newLines: newLines)
            : nil
        if lookup != nil { live = [live, CoachContext.lookupBrief].compactMap { $0 }.joined(separator: "\n\n") }
        // Say what's in play — otherwise there's no way to tell from the answers
        // whether the coaching notes or the live session were picked up.
        var note = excerpt.note
        if !brief.coaching.isEmpty || !brief.goals.isEmpty { note += " · brief" }
        if !brief.research.isEmpty { note += " · evidence" }
        if draft.map({ !$0.isEmpty }) ?? false { note += " · mid-session" }
        contextNote = note

        messages.append(CoachMessage(role: .you, text: trimmed))
        let reply = CoachMessage(role: .coach, text: "", isStreaming: true, model: model,
                                 isLookup: lookup != nil)
        messages.append(reply)
        isResponding = true
        persist()   // the question survives even if the answer doesn't

        let service = ClaudeService(apiKey: key, model: model, workspaceID: workspace)
        let thisTurn = UUID()
        turn = thisTurn

        task = Task { [weak self] in
            do {
                if lookup != nil {
                    // The whole answer at once; the sources become a line of links.
                    let result = try await service.lookup(system: system, live: live, turns: turns)
                    guard let self, !Task.isCancelled else { return }
                    var text = result.text
                    if !result.sources.isEmpty {
                        let links = result.sources.map { source in
                            let title = source.title.replacingOccurrences(of: "[", with: "(")
                                                    .replacingOccurrences(of: "]", with: ")")
                            return "[\(title)](\(source.url))"
                        }
                        text += "\n\nSources: " + links.joined(separator: " · ")
                    }
                    self.append(text, to: reply.id)
                    self.setUsage(result.usage, on: reply.id)
                    self.noteStop(result.stopReason, on: reply.id)
                } else {
                for try await event in service.stream(system: system, live: live, turns: turns) {
                    guard let self, !Task.isCancelled else { return }
                    switch event {
                    case .text(let chunk): self.append(chunk, to: reply.id)
                    case .usage(let usage):
                        // Saved at once: a kill mid-stream must not lose what was billed.
                        self.setUsage(usage, on: reply.id)
                        self.persist()
                    case .stopped(let reason): self.noteStop(reason, on: reply.id)
                    }
                }
                }
                self?.seenLines = seenAfterReply
            } catch is CancellationError {
                // Left the partial answer in place on purpose.
            } catch let error as URLError where error.code == .cancelled {
                // Stop during a lookup: the request is cancelled, not failed.
            } catch {
                // Surface the failure, not the request: ClaudeError carries the
                // status and the API's reason — never the prompt or the log.
                self?.errorText = error.localizedDescription
            }
            // A stopped turn unwinding after the next began: nothing here is its.
            guard let self, self.turn == thisTurn else { return }
            self.finishStreamingMessage()
            self.isResponding = false
            self.task = nil
            self.persist()
        }
    }

    /// The on-device path: a compact brief, no key, no cost, the same fences.
    /// The context is trimmed once and retried if the model says it's too long.
    private func sendOnDevice(_ question: String, sessions: [Session],
                              brief: CoachContext.Brief, draft: SessionDraft?, muscleMap: MuscleMap) {
        guard mode == .coaching else {
            messages.append(CoachMessage(role: .you, text: question))
            errorText = "The goals interview needs Claude. Pick Sonnet, Opus or Fable for it."
            return
        }
        if let why = AppleCoach.unavailableReason {
            messages.append(CoachMessage(role: .you, text: question))
            errorText = why
            return
        }
        let history = messages.suffix(6).map { (role: $0.role == .you ? "Lifter" : "Coach", text: $0.text) }
        contextNote = "on device · digest · \(min(sessions.count, CoachContext.onDeviceSessions)) recent sessions · tools"

        messages.append(CoachMessage(role: .you, text: question))
        let reply = CoachMessage(role: .coach, text: "", isStreaming: true, model: .onDevice)
        messages.append(reply)
        isResponding = true
        persist()

        task = Task { [weak self] in
            var budget = CoachContext.onDeviceBudget
            var attempt = 0
            while true {
                attempt += 1
                let prompt = CoachContext.onDevicePrompt(question: question, history: Array(history),
                                                         sessions: sessions, brief: brief, draft: draft,
                                                         budget: budget)
                do {
                    for try await whole in AppleCoach.respond(question: question, prompt: prompt,
                                                              sessions: sessions, muscleMap: muscleMap) {
                        guard let self, !Task.isCancelled else { return }
                        self.replace(whole, on: reply.id)
                    }
                    break
                } catch is CancellationError {
                    break
                } catch {
                    guard let self else { return }
                    if attempt == 1, AppleCoach.isContextTooLong(error) {
                        budget /= 2   // half the sessions, same question
                        continue
                    }
                    self.errorText = AppleCoach.describe(error)
                    break
                }
            }
            guard let self else { return }
            self.finishStreamingMessage()
            self.isResponding = false
            self.task = nil
            self.persist()
        }
    }

    /// The on-device stream hands over the whole text so far, not a chunk.
    private func replace(_ text: String, on id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text = text
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += chunk
    }

    private func setUsage(_ usage: ClaudeService.Usage, on id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].usage = usage
    }

    /// An answer that ended for a reason other than being finished says so —
    /// beside the bubble, not in it: what the app says must never go back to
    /// the model as its own earlier words.
    private func noteStop(_ reason: String?, on id: UUID) {
        guard let reason, let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].stop = reason
    }

    private func finishStreamingMessage() {
        guard let idx = messages.lastIndex(where: { $0.isStreaming }) else { return }
        messages[idx].isStreaming = false
        // Whatever it cost counts against the month, finished or not — a
        // partial answer was billed all the same. A stopped stream never gets
        // its output count, so it is estimated from what arrived.
        if var usage = messages[idx].usage, let model = messages[idx].model, !recorded.contains(messages[idx].id) {
            if usage.output == 0, !messages[idx].text.isEmpty { usage.output = messages[idx].text.count / 4 }
            messages[idx].usage = usage
            recorded.insert(messages[idx].id)
            CoachSpend.shared.record(model.cost(usage))
        }
        // A request that failed before a single token arrived leaves an empty
        // bubble behind; drop it and let `errorText` do the talking. A refusal
        // is empty too, and stays: its note is the answer.
        if messages[idx].stop == nil, messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        }
    }
}
