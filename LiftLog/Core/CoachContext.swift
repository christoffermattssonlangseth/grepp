import Foundation

/// Assembles the text handed to the coaching model: who it is, what the
/// `training.md` tokens mean, and as much of the log as fits a character budget.
///
/// Pure and Foundation-only, so it sits in the tested Core layer next to the
/// parser it mirrors — and so the log text is assembled in exactly one place
/// that never prints, logs or caches it. Callers pass the result straight to the
/// model; nothing here writes to disk or the console.
enum CoachContext {

    /// How much of the log to send, in characters. The file is one line per
    /// exercise per day, so several years of training still lands well under this
    /// — the cap only bites on an unusually long history, where the most recent
    /// sessions are the ones worth spending context on anyway.
    static let defaultBudget = 24_000

    /// The slice of history that fits the budget, newest-biased.
    struct LogExcerpt: Equatable {
        /// The log lines, in `training.md` format (ascending by date). Empty when
        /// there is nothing logged yet.
        var text: String
        /// How many sessions `text` covers.
        var sessionCount: Int
        /// How many older sessions were left out to fit the budget.
        var omittedCount: Int
        var firstDate: String?
        var lastDate: String?

        var isEmpty: Bool { sessionCount == 0 }

        /// One line for the UI, so it's visible what the model was actually shown.
        var note: String {
            guard let firstDate, let lastDate else { return "No training logged yet." }
            let span = sessionCount == 1 ? "1 session (\(lastDate))" : "\(sessionCount) sessions \(firstDate) → \(lastDate)"
            return omittedCount == 0 ? "Context: \(span)." : "Context: \(span) · \(omittedCount) older omitted."
        }
    }

    /// Take whole sessions from the newest backwards until the budget runs out.
    /// Sessions are never split — half a day's work reads as a day where you did
    /// less, which is exactly the wrong thing to hand a coach. At least one
    /// session is always included, even if it alone exceeds the budget.
    static func excerpt(from sessions: [Session], budget: Int = defaultBudget) -> LogExcerpt {
        let ascending = sessions.sorted { $0.date < $1.date }
        guard !ascending.isEmpty else {
            return LogExcerpt(text: "", sessionCount: 0, omittedCount: 0, firstDate: nil, lastDate: nil)
        }

        var included: [Session] = []
        var size = 0
        for session in ascending.reversed() {
            let cost = WorkoutParser.serialize([session]).count
            if !included.isEmpty && size + cost > budget { break }
            included.insert(session, at: 0)
            size += cost
        }

        return LogExcerpt(
            text: WorkoutParser.serialize(included),
            sessionCount: included.count,
            omittedCount: ascending.count - included.count,
            firstDate: included.first?.dateString,
            lastDate: included.last?.dateString
        )
    }

    /// The system prompt: the coach's brief, the format key, and the log.
    ///
    /// It goes in `system` rather than in the question, so it stays byte-identical
    /// across a conversation's turns and can be prompt-cached.
    static func systemPrompt(for excerpt: LogExcerpt, today: Date = Date()) -> String {
        let todayString = Session.dateFormatter.string(from: today)

        let coverage: String
        if excerpt.isEmpty {
            coverage = "The log is empty — no workouts have been recorded yet."
        } else if excerpt.omittedCount > 0 {
            coverage = """
            The log below holds the most recent \(excerpt.sessionCount) sessions \
            (\(excerpt.firstDate ?? "") to \(excerpt.lastDate ?? "")). \
            \(excerpt.omittedCount) older sessions exist but were left out to fit — \
            say so if a question needs history older than \(excerpt.firstDate ?? "that").
            """
        } else if excerpt.sessionCount == 1 {
            coverage = "The log below is complete: the single recorded session, on \(excerpt.lastDate ?? "")."
        } else {
            coverage = """
            The log below is complete: all \(excerpt.sessionCount) recorded sessions, \
            \(excerpt.firstDate ?? "") to \(excerpt.lastDate ?? "").
            """
        }

        return """
        You are a strength-training coach, reading one athlete's own training log.

        FORMAT. The log is a plain-text file, one line per exercise per day:

            2026-08-30 deadlift 82.5x8 82.5x8 82.5x8
            2026-08-30 chin-ups bwx6 bwx6 bw+5x6

        The date is ISO `YYYY-MM-DD`, and every line sharing a date is one session. \
        Exercise names are lowercase kebab-case. Each set is a `weightxreps` token: \
        `82.5x8` is 82.5 kg for 8 reps, `bwx6` is bodyweight for 6 reps, and `bw+5x6` \
        is bodyweight plus 5 kg for 6 reps. All loads are kilograms.

        WHAT ISN'T THERE. The log records loads and reps only. There is no RPE, no \
        rest time, no set order beyond left-to-right, no bodyweight figure, and no \
        note of sleep, illness or missed sessions. A gap between dates might be a \
        deload, a holiday or an injury — you cannot tell which, so ask rather than assume.

        HOW TO ANSWER. Today is \(todayString). \(coverage)

        Reason from the numbers in front of you and name them: cite the dates and \
        loads a conclusion rests on. Never invent a session, a lift or a number that \
        isn't in the log. When the log is too thin to support an answer, say so plainly \
        and say what would settle it. Prefer a specific, actionable recommendation over \
        general training theory — and keep it short: this is read on a phone, often \
        between sets. You are not a doctor; suggest medical advice for pain, never \
        diagnose it.

        <training-log>
        \(excerpt.text)</training-log>
        """
    }

    /// Starter questions offered on an empty Coach screen.
    static let suggestedQuestions = [
        "How is my squat progressing?",
        "Which lifts have stalled the longest?",
        "Should today be heavy or light, given last week?",
        "What am I under-training?",
    ]
}
