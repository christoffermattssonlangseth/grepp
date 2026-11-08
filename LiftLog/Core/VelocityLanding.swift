import Foundation

/// Which set a measurement from BarVelo belongs to.
///
/// The owner trains alone: they open BarVelo from the Log tab, lift, and come
/// back. By then the set may already be landed — from the lock screen during
/// the rest, or with a tap before the speeds came back — and the next tap
/// would carry the speeds onto the wrong set, and Finish would write the
/// wrong `set N`. These rules decide, from what is on screen, where the
/// speeds go. A measurement that goes nowhere is never dropped: it is queued
/// unnumbered, as before.
extension VelocitySet {

    /// The set is at the load this was measured at: the same kilos to the
    /// hundredth, or bodyweight with the same added load.
    func matchesLoad(of set: WorkSet) -> Bool {
        switch (load, set.weight) {
        case let (a?, b?): return abs(a - b) <= 0.01 + 1e-9
        case (nil, nil): return abs((added ?? 0) - (set.added ?? 0)) <= 0.01 + 1e-9
        default: return false
        }
    }

    /// The same handoff, whatever reps-left answer was given in Grepp since:
    /// a second delivery of one link is one set.
    func isSameHandoff(as other: VelocitySet) -> Bool {
        var a = self, b = other
        a.left = nil; b.left = nil
        return a == b
    }

    /// The newest set to offer "attach to set N" for, as its index in `sets`:
    /// one landed after BarVelo was opened (`setsWhenOpened` is how many were
    /// landed then; nil when unknown), with no speeds of its own yet, at this
    /// measurement's load. Nil otherwise: the speeds wait for the next set.
    func attachCandidate(sets: [WorkSet], measurements: [UUID: VelocitySet], setsWhenOpened: Int?) -> Int? {
        guard let opened = setsWhenOpened, sets.count > opened, let last = sets.last,
              measurements[last.id] == nil, matchesLoad(of: last) else { return nil }
        return sets.count - 1
    }
}

extension SessionDraft {

    /// A set was just landed outside the Log screen (the lock screen's
    /// button): the held measurement rides on it when it was for this lift and
    /// this load, as a tap in the Log tab would have it. A measurement at
    /// another load stays held for the next set. True when it was taken.
    @discardableResult
    mutating func takeHeldMeasurement() -> Bool {
        guard let held = measured, let set = sets.last, !name.isEmpty,
              Analytics.matches(name, held.lift), measurements?[set.id] == nil,
              held.matchesLoad(of: set) else { return false }
        var m = measurements ?? [:]
        m[set.id] = held
        measurements = m
        measured = nil
        return true
    }
}

extension VelocitySet {

    /// The Log tab's "reps left?" answer: fail · 0 · 1 · 2 · 3+, or none.
    /// Written to the line as `fail` or `left N`; `3+` as `left 3`, at least
    /// three, which is as far as a lifter alone can tell.
    enum RepsLeftChoice: CaseIterable, Hashable {
        case none, fail, zero, one, two, threePlus

        init(_ left: Left?) {
            switch left {
            case nil: self = .none
            case .failed?: self = .fail
            case .reps(let n)?: self = n <= 0 ? .zero : n == 1 ? .one : n == 2 ? .two : .threePlus
            }
        }

        var left: Left? {
            switch self {
            case .none: return nil
            case .fail: return .failed
            case .zero: return .reps(0)
            case .one: return .reps(1)
            case .two: return .reps(2)
            case .threePlus: return .reps(3)
            }
        }

        /// On a chip.
        var short: String {
            switch self {
            case .none: return "–"
            case .fail: return "fail"
            case .zero: return "0"
            case .one: return "1"
            case .two: return "2"
            case .threePlus: return "3+"
            }
        }

        /// Read out: `failed rep`, `0 left: nothing left, no rep missed`.
        var label: String {
            switch self {
            case .none: return "not answered"
            case .fail: return "failed a rep"
            case .zero: return "0 left, no rep missed"
            case .one: return "1 left"
            case .two: return "2 left"
            case .threePlus: return "3 or more left"
            }
        }
    }
}
