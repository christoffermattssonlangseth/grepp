import Foundation

/// The exercise being logged right now, so a backgrounded-and-killed app costs
/// nothing: the sets already landed, what's in the fields, the plan and queue
/// Coach handed over, and when the rest clock started.
struct SessionDraft: Codable, Equatable {
    /// Saved as its day, so a kill and a flight don't move the lift.
    @DayCoded var date: Date
    var name: String
    var sets: [WorkSet]
    var isBodyweight: Bool
    var weightText: String
    var addedText: String
    var repsText: String
    var plan: [WorkSet]?
    var queue: [ExerciseEntry]
    var restStart: Date?
    /// The day was picked on purpose, so a backfill restored after a kill
    /// doesn't ask about its day again. Nil in drafts saved before it was kept.
    var dateChosen: Bool? = nil
    /// The logged line the lift was opened from, which finishing replaces.
    var target: LineRef? = nil
    /// A set BarVelo measured that hasn't been landed yet, so a kill between
    /// the handoff and the tap doesn't lose it. Nil in older drafts.
    var measured: VelocitySet? = nil
    /// Measurements riding on landed sets, by the set's id, until Finish
    /// writes them to velocity.md. Nil in older drafts.
    var measurements: [UUID: VelocitySet]? = nil

    /// Nothing worth keeping: no lift chosen, nothing landed, nothing queued.
    /// Numbers typed but not yet added don't count on their own.
    var isEmpty: Bool { name.isEmpty && sets.isEmpty && queue.isEmpty }

    /// The set the plan says comes next, if the plan has one left.
    var nextPlanned: WorkSet? {
        guard let plan, sets.count < plan.count else { return nil }
        return plan[sets.count]
    }

    /// What "same again" lands: the next planned set, else the last one landed.
    /// Nil when nothing has been landed and nothing is planned.
    var sameAgainSet: WorkSet? {
        nextPlanned ?? sets.last
    }
}
