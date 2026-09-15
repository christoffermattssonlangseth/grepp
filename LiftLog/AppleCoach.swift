import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model as a coach: free, private, and small.
///
/// The Foundation Models framework runs a language model on the phone with
/// a context window of a few thousand tokens — a fraction of what Claude is
/// handed. So this coach gets a compact brief (`CoachContext.onDevicePrompt`)
/// rather than the whole log, and answers questions about the last few
/// weeks rather than designing a year. Everything it writes goes through the
/// same fences and cards as Claude's answers.
@MainActor
enum AppleCoach {
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

    /// The answer as it grows: each element is the whole text so far.
    static func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    do {
                        let session = LanguageModelSession(instructions: instructions)
                        for try await partial in session.streamResponse(to: prompt) {
                            // The element is the partial text (or a snapshot
                            // carrying it under `content`), cumulative.
                            let text = (partial as? String)
                                ?? (Mirror(reflecting: partial).descendant("content") as? String)
                                ?? ""
                            if !text.isEmpty { continuation.yield(text) }
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
    static func describe(_ error: Error) -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize:
                return "Too much for the on-device model even trimmed. Start a new chat, or ask Claude."
            case .guardrailViolation:
                return "Apple's model declined to answer that one."
            default:
                return "The on-device model couldn't answer: \(e.localizedDescription)"
            }
        }
        #endif
        return error.localizedDescription
    }
}
