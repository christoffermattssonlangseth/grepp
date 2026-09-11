import Foundation

/// One prescribed exercise and what became of it.
///
/// The log holds what was done; only the app knows what the coach asked for.
/// Keeping the two side by side is what lets the next prescription start from
/// what actually happened — a set cut short, a jump taken early, a lift skipped —
/// rather than from the plan as written.
struct PlanRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    /// When the plan was loaded into the Log tab.
    var prescribed: Date
    var name: String
    var plan: [WorkSet]
    /// The log date the exercise was finished under; nil until it is.
    var done: Date?
    /// What was actually lifted. Empty until done.
    var sets: [WorkSet] = []

    var isDone: Bool { done != nil }

    /// How the sets compare with the plan, in a few words. Nil when as prescribed.
    var verdict: String? {
        guard isDone else { return nil }
        if sets.map(\.token) == plan.map(\.token) { return nil }

        let load: (WorkSet) -> Double = { $0.weight ?? $0.added ?? 0 }
        var notes: [String] = []

        let plannedTop = plan.map(load).max() ?? 0
        let doneTop = sets.map(load).max() ?? 0
        if doneTop > plannedTop { notes.append("heavier") }
        if doneTop < plannedTop { notes.append("lighter") }

        if sets.count < plan.count {
            notes.append("\(plan.count - sets.count) \(plan.count - sets.count == 1 ? "set" : "sets") short")
        } else if sets.count > plan.count {
            notes.append("\(sets.count - plan.count) extra \(sets.count - plan.count == 1 ? "set" : "sets")")
        } else {
            let plannedReps = plan.map(\.reps).reduce(0, +)
            let doneReps = sets.map(\.reps).reduce(0, +)
            if doneReps < plannedReps { notes.append("\(plannedReps - doneReps) \(plannedReps - doneReps == 1 ? "rep" : "reps") short") }
            if doneReps > plannedReps { notes.append("\(doneReps - plannedReps) \(doneReps - plannedReps == 1 ? "rep" : "reps") over") }
        }
        return notes.isEmpty ? "different sets" : notes.joined(separator: ", ")
    }
}

extension Array where Element == PlanRecord {
    /// Add a prescription. An undone record for the same lift is replaced — the
    /// same session loaded twice is one plan, not two.
    mutating func prescribe(_ entries: [ExerciseEntry], on date: Date) {
        for entry in entries {
            removeAll { !$0.isDone && $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }
            append(PlanRecord(prescribed: date, name: entry.name, plan: entry.sets))
        }
    }

    /// The lift was finished: pin what was done to its most recent open plan.
    /// Nothing happens when no plan was open — an unplanned lift is just the log.
    mutating func complete(_ entry: ExerciseEntry, on date: Date) {
        guard let idx = lastIndex(where: {
            !$0.isDone && $0.name.caseInsensitiveCompare(entry.name) == .orderedSame
        }) else { return }
        self[idx].done = date
        self[idx].sets = entry.sets
    }

    /// A lift — or the whole day, when `name` is nil — was moved in the log:
    /// what was done under the old date is now done under the new one.
    mutating func move(name: String?, from old: Date, to new: Date) {
        let key = Session.dateFormatter.string(from: old)
        for i in indices {
            guard let done = self[i].done, Session.dateFormatter.string(from: done) == key,
                  name.map({ self[i].name.caseInsensitiveCompare($0) == .orderedSame }) ?? true
            else { continue }
            self[i].done = new
        }
    }

    /// Drop what's too old to matter to the next prescription.
    mutating func prune(before cutoff: Date) {
        removeAll { $0.prescribed < cutoff && ($0.done ?? $0.prescribed) < cutoff }
    }
}
