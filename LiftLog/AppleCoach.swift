import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model as a coach: free, private, and small.
///
/// The Foundation Models framework runs a language model on the phone with a
/// context window of a few thousand tokens — a fraction of what Claude is
/// handed. So this coach is not given the log. It gets a compact brief
/// (`CoachContext.onDevicePrompt`) and three *tools* it can call back into the
/// app with when a question needs more: one lift's history, the last days of
/// the log, sets per muscle. And where the answer has a shape — today's
/// session, history the lifter describes — it is asked for that shape as a
/// type (guided generation) rather than as prose with a fence in it, so a
/// prescription can't come back malformed. The assembled reply then goes
/// through the same fences and cards as Claude's.
///
/// Qwen (`QwenModel`) runs through this same path: MLX's adapter makes it a
/// FoundationModels `LanguageModel`, so the session, the tools and the typed
/// answers are the same code, and only the model handed to the session and
/// the size of the brief differ.
@MainActor
enum AppleCoach {
    /// Which on-device model answers.
    enum Engine {
        case apple, qwen

        var name: String { self == .apple ? "Apple's model" : "Qwen" }
    }

    /// Whether the framework is here and the phone can run the model at all.
    /// The picker offers "On device" only when this is true.
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .unavailable(.deviceNotEligible) = SystemLanguageModel.default.availability { return false }
            return true
        }
        #endif
        return false
    }

    /// Nil when the model can answer now; otherwise why not, in words.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return "This iPhone can't run Apple's on-device model."
                case .appleIntelligenceNotEnabled:
                    return "Turn on Apple Intelligence in Settings to use the on-device model."
                case .modelNotReady:
                    return "Apple's model is still being set up on this phone. Try again in a while."
                @unknown default:
                    return "Apple's on-device model isn't available right now."
                }
            }
        }
        #endif
        return "Apple's on-device model needs iOS 26 or later."
    }

    /// What the lifter's message is asking for. Decided by the model itself,
    /// in one small typed call, so the shape of the answer can follow.
    enum Intent: String { case prescribe, importHistory, question }

    /// The answer as it grows: each element is the whole text so far. A
    /// structured answer (a session, imported history) arrives in one piece,
    /// already assembled with its fence.
    static func respond(question: String, prompt: CoachContext.OnDevicePrompt,
                        sessions: [Session], muscleMap: MuscleMap, engine: Engine = .apple,
                        programme: Programme = Programme.parse(""),
                        bar: @escaping (String) -> Double = { _ in 20 }, inventory: PlateInventory = .standard,
                        today: Date = Date()) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    do {
                        let tools: [any Tool] = [
                            LiftHistoryTool(sessions: sessions),
                            RecentSessionsTool(sessions: sessions, today: today),
                            MuscleSetsTool(sessions: sessions, map: muscleMap, today: today),
                        ]
                        switch try await classify(question, engine: engine) {
                        case .prescribe:
                            // Which day is next, and its loads, are arithmetic: the app
                            // answers, and the model is asked only when the log and
                            // the programme say nothing.
                            if let next = CoachContext.nextSession(question: question, sessions: sessions,
                                                                   programme: programme, bar: bar, inventory: inventory) {
                                continuation.yield(CoachContext.prescriptionReply(note: next.note, lifts: next.lifts))
                                break
                            }
                            // Qwen's brief already holds the recent sessions; its tool rounds
                            // only re-fetched them, and tripled the time to a plan.
                            let session = try makeSession(engine, tools: engine == .qwen ? [] : tools,
                                                          instructions: CoachContext.onDevicePlanInstructions)
                            let plan = try await session.respond(to: prompt.prompt, generating: PlannedSession.self).content
                            // The loads are the rule's, not the model's: it was handed
                            // them, and anything it changed is put back.
                            let lifts = CoachContext.heldToRule(plan.lifts.map(\.generated), sessions: sessions)
                            let note = CoachContext.ruleNote(for: lifts, sessions: sessions)
                                ?? CoachContext.plainNote(plan.note)
                            continuation.yield(CoachContext.prescriptionReply(note: note, lifts: lifts))
                        case .importHistory:
                            let session = try makeSession(engine, instructions: CoachContext.onDeviceImportInstructions)
                            let history = try await session.respond(to: prompt.prompt, generating: DescribedHistory.self).content
                            continuation.yield(CoachContext.importReply(
                                note: history.note,
                                days: history.days.map { (date: $0.date, lifts: $0.lifts.map(\.generated)) }))
                        case .question:
                            let session = try makeSession(engine, tools: tools, instructions: prompt.instructions)
                            for try await partial in session.streamResponse(to: prompt.prompt) {
                                // Each snapshot carries the whole text so far.
                                let text = partial.content
                                if !text.isEmpty { continuation.yield(text) }
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    return
                }
                #endif
                continuation.finish(throwing: OnDeviceError.unavailable(unavailableReason ?? "Not available."))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum OnDeviceError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            if case .unavailable(let why) = self { return why }
            return nil
        }
    }

    /// Whether the failure was the prompt not fitting — the one case worth
    /// a retry with less context.
    static func isContextTooLong(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let e = error as? LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = e { return true }
        }
        #endif
        return false
    }

    /// The failure in the lifter's terms.
    static func describe(_ error: Error, engine: Engine = .apple) -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize:
                return "Too much for \(engine.name) even trimmed. Start a new chat, or ask Claude."
            case .guardrailViolation:
                return "\(engine.name) declined to answer that one."
            default:
                return "\(engine.name) couldn't answer: \(e.localizedDescription)"
            }
        }
        #endif
        return error.localizedDescription
    }

    #if canImport(FoundationModels)
    /// A session on the engine's model. Qwen's adapter exists from iOS 27.
    @available(iOS 26.0, *)
    private static func makeSession(_ engine: Engine, tools: [any Tool] = [],
                                    instructions: String) throws -> LanguageModelSession {
        switch engine {
        case .apple:
            return LanguageModelSession(tools: tools, instructions: instructions)
        case .qwen:
            guard #available(iOS 27.0, *) else {
                throw OnDeviceError.unavailable("Qwen on device needs iOS 27 or later.")
            }
            return LanguageModelSession(model: QwenModel.model, tools: tools, instructions: instructions)
        }
    }

    /// One small typed call: what kind of answer does the message want.
    @available(iOS 26.0, *)
    private static func classify(_ question: String, engine: Engine) async throws -> Intent {
        let session = try makeSession(engine, instructions: """
            Classify a message to a strength coach. "prescribe" when they ask what to \
            train, do, lift or squat today or next, or for a session or workout. \
            "importHistory" when they report training they have already done, with \
            lifts and numbers, to be added to their log. "question" for anything else.
            """)
        // Wrapped in a struct: MLX's adapter hands a bare enum back with its
        // JSON quotes on ("\"prescribe\""), which FoundationModels then can't
        // match to a case. A field of a struct decodes on both models.
        let kind = try await session.respond(to: question, generating: MessageClass.self).content.kind
        switch kind {
        case .prescribe: return .prescribe
        case .importHistory: return .importHistory
        case .question: return .question
        }
    }
    #endif
}

#if canImport(FoundationModels)

// MARK: - The shapes the model fills in

@available(iOS 26.0, *)
@Generable(description: "What kind of answer a message to a strength coach wants")
nonisolated enum MessageKind: String {
    case prescribe, importHistory, question
}

@available(iOS 26.0, *)
@Generable(description: "The kind of answer a message to a strength coach wants")
nonisolated struct MessageClass {
    var kind: MessageKind
}

@available(iOS 26.0, *)
@Generable(description: "One working set")
nonisolated struct PlannedSet {
    @Guide(description: "Load in kilograms; 0 for a bodyweight set")
    var weightKg: Double
    @Guide(description: "Repetitions", .range(1...50))
    var reps: Int
}

@available(iOS 26.0, *)
@Generable(description: "One lift with its sets, as done")
nonisolated struct PlannedLift {
    @Guide(description: "The lift's name as the log has it: lowercase, hyphens for spaces, e.g. squat, bench, chin-ups")
    var name: String
    @Guide(description: "The working sets, in order", .count(1...6))
    var sets: [PlannedSet]

    var generated: CoachContext.GeneratedLift {
        CoachContext.GeneratedLift(name: name, sets: sets.map { (kg: $0.weightKg, reps: $0.reps) })
    }
}

@available(iOS 26.0, *)
@Generable(description: "One lift prescribed for today, with its working sets")
nonisolated struct PrescribedLift {
    @Guide(description: "The lift's name as the log has it: lowercase, hyphens for spaces, e.g. squat, bench, chin-ups")
    var name: String
    // The instructions ask for three to five; the shape holds a small model
    // to it, where 1...6 let it write a single set and stop.
    @Guide(description: "The working sets, in order", .count(3...5))
    var sets: [PlannedSet]

    var generated: CoachContext.GeneratedLift {
        CoachContext.GeneratedLift(name: name, sets: sets.map { (kg: $0.weightKg, reps: $0.reps) })
    }
}

@available(iOS 26.0, *)
@Generable(description: "Today's session, prescribed from the lifter's own log")
nonisolated struct PlannedSession {
    @Guide(description: "One or two short plain sentences, no markdown, naming the numbers and dates the plan rests on")
    var note: String
    @Guide(description: "Two to four lifts, in the order to do them", .count(2...4))
    var lifts: [PrescribedLift]
}

@available(iOS 26.0, *)
@Generable(description: "One day of training the lifter described")
nonisolated struct DescribedDay {
    @Guide(description: "The date as yyyy-MM-dd")
    var date: String
    @Guide(description: "The lifts done that day", .count(1...10))
    var lifts: [PlannedLift]
}

@available(iOS 26.0, *)
@Generable(description: "Training the lifter says they did, as log entries")
nonisolated struct DescribedHistory {
    @Guide(description: "One sentence on anything assumed, such as a date; empty if nothing was")
    var note: String
    @Guide(description: "One entry per day, oldest first", .count(1...14))
    var days: [DescribedDay]
}

// MARK: - The tools: the model asks the app rather than being handed the log

@available(iOS 26.0, *)
nonisolated struct LiftHistoryTool: Tool {
    let name = "liftHistory"
    let description = "The last sessions of one lift from the training log, newest first, with its best set ever. Use it for any question about how a lift has gone."
    let sessions: [Session]

    @Generable
    struct Arguments {
        @Guide(description: "The lift, as named in the log, e.g. squat, bench, deadlift, chin-ups")
        var lift: String
        @Guide(description: "How many sessions to show", .range(1...8))
        var count: Int
    }

    // The model calls from its own executor; the log helpers live on the main actor.
    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { CoachContext.liftLines(arguments.lift, in: sessions, count: arguments.count) }
    }
}

@available(iOS 26.0, *)
nonisolated struct RecentSessionsTool: Tool {
    let name = "recentSessions"
    let description = "The training log's own lines from the last N days, oldest first. Use it to see what was trained lately across all lifts."
    let sessions: [Session]
    let today: Date

    @Generable
    struct Arguments {
        @Guide(description: "How many days back to look", .range(1...60))
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { CoachContext.recentLines(days: arguments.days, in: sessions, today: today) }
    }
}

@available(iOS 26.0, *)
nonisolated struct MuscleSetsTool: Tool {
    let name = "muscleSets"
    let description = "Working sets per muscle for each of the last N weeks, counted by the app. Use it for questions about volume, balance or what's been neglected."
    let sessions: [Session]
    let map: MuscleMap
    let today: Date

    @Generable
    struct Arguments {
        @Guide(description: "How many weeks", .range(1...8))
        var weeks: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { CoachContext.muscleSetLines(weeks: arguments.weeks, in: sessions, map: map, today: today) }
    }
}

#endif
