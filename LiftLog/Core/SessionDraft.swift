import Foundation

/// The exercise being logged right now, so a backgrounded-and-killed app costs
/// nothing: the sets already landed, what's in the fields, the plan and queue
/// Coach handed over, and when the rest clock started.
struct SessionDraft: Codable, Equatable {
    var date: Date
    var name: String
    var sets: [WorkSet]
    var isBodyweight: Bool
    var weightText: String
    var addedText: String
    var repsText: String
    var plan: [WorkSet]?
    var queue: [ExerciseEntry]
    var restStart: Date?

    /// Nothing worth keeping: no lift chosen, nothing landed, nothing queued.
    /// Numbers typed but not yet added don't count on their own.
    var isEmpty: Bool { name.isEmpty && sets.isEmpty && queue.isEmpty }
}
