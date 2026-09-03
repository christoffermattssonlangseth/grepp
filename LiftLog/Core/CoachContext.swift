import Foundation

/// Assembles the text handed to the coaching model: who it is, what the
/// `training.md` tokens mean, and as much of the log as fits a character budget.
///
/// Pure and Foundation-only, so it sits in the tested Core layer next to the
/// parser it mirrors — and so the log text is assembled in exactly one place
/// that never prints, logs or caches it. Callers pass the result straight to the
/// model; nothing here writes to disk or the console.
enum CoachContext {

    /// How much of the log to send, in characters.
    ///
    /// An exercise line runs about 34 characters, so this carries roughly 3,500
    /// of them — around five years at three sessions a week. The point is that a
    /// real personal log goes over in full: both models take a million tokens, so
    /// there is no reason to be stingy, and this is ~34k tokens, a few cents a
    /// question at most and less once the prompt cache warms. The cap only bites
    /// on a genuinely long history, where the newest sessions are the ones worth
    /// spending context on anyway.
    static let defaultBudget = 120_000

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

        Ground every answer in the numbers and name them: cite the dates and loads a \
        conclusion rests on. Never invent a session, a lift or a number that isn't in \
        the log.

        PRESCRIBE, DON'T LECTURE. When asked what to do next — a single session, a \
        week, how to take a lift forward — answer with concrete numbers: the exercise, \
        the load in kg, and the sets and reps, chosen from what the log shows has \
        actually been working. "Squat 3x5 at 87.5 kg, up from 85x5 last Thursday" is an \
        answer; "focus on progressive overload" is not. Give the reasoning in a line or \
        two after the prescription, not before it. Size each jump from the increments \
        this lifter has been making, not a textbook default.

        CALL STALLS. When a lift's top set hasn't moved in three or more sessions, say \
        so and prescribe a specific way out — hold the load and add a rep, cut ~10% and \
        build back, or swap the movement — rather than repeating the same jump that \
        already failed to land.

        SAY WHAT YOU CAN'T SEE. When the log won't support an answer, say so plainly and \
        say what would settle it. You cannot see RPE, bodyweight, sleep, illness, or why \
        a gap happened, so ask before reading a gap as lost progress.

        You can only read this log — you cannot add to it, change it, or schedule \
        anything. If the user wants a session recorded, tell them to log it in the Log tab.

        Keep it short: this is read on a phone, often between sets. Lead with the \
        recommendation. You are not a doctor; suggest medical advice for pain, never \
        diagnose it.

        <training-log>
        \(excerpt.text)</training-log>
        """
    }

    /// Starter questions offered on an empty Coach screen. Weighted towards "what
    /// should I do next", since that's what a coach is for.
    static let suggestedQuestions = [
        "What should my next squat session be?",
        "Plan next week from my recent sessions.",
        "Which lifts have stalled, and what do I do about it?",
        "How is my squat progressing?",
    ]
}
