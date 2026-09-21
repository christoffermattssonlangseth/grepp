import Foundation

/// A single point on a progression chart: one session of one lift.
struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    /// The day's sets for the lift as the log has them: "100x5 102.5x5 102.5x3".
    var tokens: String = ""
    /// The lift's name as the log spelled it that day.
    var name: String = ""
    /// The day this metric first went past everything before it.
    var isRecord: Bool = false
}

/// The change between two points on a series.
struct TrendChange {
    let delta: Double
    /// Nil when the starting value was 0 — a percentage of nothing.
    let percent: Double?
    var isUp: Bool { delta > 0 }
    var isFlat: Bool { delta == 0 }
}

/// Progression metrics derived from the logged sessions. Purely lift-focused —
/// no personal targets, just how each movement is trending.
enum Analytics {
    enum Metric: String, CaseIterable, Identifiable {
        case topSet = "Top set"      // heaviest weight lifted — the direct intensity signal
        case oneRepMax = "Est. 1RM"  // derived, for comparing across rep schemes
        case addedLoad = "Added load" // extra load on a bodyweight lift (bw+X), where weight progresses
        case maxReps = "Max reps"    // for bodyweight lifts, where reps are the progression
        var id: String { rawValue }

        var unit: String {
            switch self {
            case .topSet, .oneRepMax, .addedLoad: return "kg"
            case .maxReps: return "reps"
            }
        }
    }

    /// Working sets in a session — every logged set is one. Sets, not kilos:
    /// tonnage rewards a light leg press over a heavy triple and says nothing
    /// about where the work went, and the research on volume counts sets.
    static func setCount(of session: Session) -> Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }

    // MARK: - One lift, whatever the log calls it

    /// Whether two names are the same lift: case, spaces and the known
    /// aliases aside ("bench", "Bench press" and "bench-press" are one).
    static func matches(_ a: String, _ b: String) -> Bool {
        MuscleMap.canonical(a) == MuscleMap.canonical(b)
    }

    /// The lift's entries on one day — more than one when the file has two
    /// lines for it, which a hand-edited log can.
    static func entries(_ name: String, in session: Session) -> [ExerciseEntry] {
        session.exercises.filter { matches($0.name, name) }
    }

    // MARK: - Training days

    /// One calendar day on the weeks grid.
    struct TrainingDay: Equatable, Identifiable {
        var id: String { key }
        /// The day as the log keys it: yyyy-MM-dd.
        let key: String
        /// Local midnight.
        let date: Date
        /// Working sets that day; nil when nothing was logged.
        let sets: Int?
        var trained: Bool { sets != nil }
    }

    /// Seven days, Monday first. A day in the future is nil.
    struct TrainingWeek: Equatable, Identifiable {
        var id: Date { start }
        let start: Date
        let days: [TrainingDay?]

        var sessions: Int { days.compactMap { $0 }.filter(\.trained).count }
        var sets: Int { days.compactMap { $0?.sets }.reduce(0, +) }
    }

    /// The last `weeks` weeks ending on `today`'s week, oldest first, each
    /// aligned Monday to Sunday. Days are matched on the log's own date key so
    /// a session logged as 2026-09-04 lands on 4 September wherever the phone is.
    /// The calendar is expected to share the file's time zone
    /// (`Session.calendar`); its days are keyed in that zone.
    static func weekGrid(weeks: Int, endingOn today: Date = Date(),
                         calendar: Calendar = .current, in sessions: [Session]) -> [TrainingWeek] {
        guard weeks > 0 else { return [] }
        var setsByDay: [String: Int] = [:]
        for session in sessions {
            setsByDay[session.dateString, default: 0] += setCount(of: session)
        }

        let keyFormatter = DateFormatter()
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.timeZone = calendar.timeZone
        keyFormatter.dateFormat = "yyyy-MM-dd"

        let todayStart = calendar.startOfDay(for: today)
        // Calendar weekdays run Sunday = 1 … Saturday = 7; a gym week starts Monday.
        let mondayOffset = (calendar.component(.weekday, from: todayStart) + 5) % 7
        guard let thisMonday = calendar.date(byAdding: .day, value: -mondayOffset, to: todayStart)
        else { return [] }

        return (0..<weeks).reversed().compactMap { back -> TrainingWeek? in
            guard let monday = calendar.date(byAdding: .day, value: -7 * back, to: thisMonday)
            else { return nil }
            let days = (0..<7).map { offset -> TrainingDay? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: monday),
                      date <= todayStart else { return nil }
                let key = keyFormatter.string(from: date)
                return TrainingDay(key: key, date: date, sets: setsByDay[key])
            }
            return TrainingWeek(start: monday, days: days)
        }
    }

    /// Epley estimated one-rep max. A single is its own max, and the formula
    /// is only trusted to a dozen reps: past that it turns a light back-off
    /// set into a phantom record, so the reps are capped there.
    static func epley(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1 + Double(min(reps, 12)) / 30)
    }

    /// All sets ever logged for an exercise, under any of its spellings.
    static func allSets(_ name: String, in sessions: [Session]) -> [WorkSet] {
        sessions.flatMap { session in entries(name, in: session).flatMap(\.sets) }
    }

    /// A personal record, if a set is one.
    enum Record: Equatable {
        case load   // heavier than anything logged for the lift
        case reps   // more reps than ever at this load
    }

    /// The load a set is judged by: the bar, or what's hung on the lifter.
    static func load(of set: WorkSet) -> Double { set.weight ?? (set.added ?? 0) }

    /// Judge one set against the lift's history. Weighted lifts compare weight;
    /// bodyweight lifts compare added load, so bw+5 beats bw and bwx9 beats bwx8.
    /// The very first set of a new lift is not a record — there's nothing to beat.
    ///
    /// `extra` is for sets landed but not yet committed: the second 90x5 today is
    /// not a record just because the first was.
    static func record(for set: WorkSet, exercise name: String,
                       in sessions: [Session], plus extra: [WorkSet] = []) -> Record? {
        let history = allSets(name, in: sessions) + extra
        guard !history.isEmpty else { return nil }

        let mine = load(of: set)
        if mine > (history.map { load(of: $0) }.max() ?? 0) { return .load }
        if let bestReps = history.filter({ load(of: $0) == mine }).map(\.reps).max(),
           set.reps > bestReps { return .reps }
        return nil
    }

    /// A lift done on the lifter's own weight (pull-ups, dips): most of its
    /// sets are bodyweight. "Most", not "all", so one line that forgot its
    /// `bw+` doesn't turn a year of chin-ups into a barbell lift with one point.
    static func isBodyweight(_ name: String, in sessions: [Session]) -> Bool {
        let sets = allSets(name, in: sessions)
        return !sets.isEmpty && sets.filter(\.isBodyweight).count * 2 > sets.count
    }

    /// Has a bodyweight lift ever carried load — bw+X, or a plain weight on a
    /// line that meant it?
    static func hasAddedLoad(_ name: String, in sessions: [Session]) -> Bool {
        allSets(name, in: sessions).contains { ($0.added ?? 0) > 0 || $0.weight != nil }
    }

    /// Metrics that make sense for this exercise. Weighted lifts lead with top-set
    /// weight (intensity); bodyweight lifts progress by reps — or by added load once
    /// you start hanging plates on (bw+X), which stays continuous from pure bodyweight.
    static func availableMetrics(_ name: String, in sessions: [Session]) -> [Metric] {
        guard isBodyweight(name, in: sessions) else { return [.topSet, .oneRepMax] }
        return hasAddedLoad(name, in: sessions) ? [.addedLoad, .maxReps] : [.maxReps]
    }

    /// One value per session date for the chosen metric, every line of the
    /// lift that day counted. A line dated after `today` is a typo, not a
    /// forecast, and stays off the chart; so does a set with no reps in it.
    static func series(_ name: String, metric: Metric, in sessions: [Session],
                       through today: Date = Date()) -> [TrendPoint] {
        sessions.compactMap { session -> TrendPoint? in
            guard session.date <= today else { return nil }
            let day = entries(name, in: session)
            let sets = day.flatMap(\.sets).filter { $0.reps > 0 }
            guard !sets.isEmpty else { return nil }

            let value: Double?
            switch metric {
            case .topSet:
                value = sets.compactMap(\.weight).max()
            case .oneRepMax:
                value = sets.compactMap { set in
                    set.weight.map { epley(weight: $0, reps: set.reps) }
                }.max()
            case .addedLoad:
                // Baseline of 0 for pure bodyweight sessions keeps the line
                // continuous; a plain weight on a bodyweight lift reads as added.
                value = sets.map { $0.added ?? ($0.weight ?? 0) }.max()
            case .maxReps:
                value = sets.map { Double($0.reps) }.max()
            }
            return value.map {
                TrendPoint(date: session.date, value: $0, tokens: sets.map(\.token).joined(separator: " "),
                           name: day.first?.name ?? name)
            }
        }
        .sorted { $0.date < $1.date }
        .flagged()
    }

    /// Every day a lift set a record, keyed by day then canonical name: a
    /// heavier set than anything before it, or more reps than ever at that
    /// load, judged the way the Log badge judges a set as it lands — every
    /// earlier day and the sets before it that day. The first day of a lift
    /// is not a record. Heavier wins over more reps when a day has both.
    static func records(in sessions: [Session]) -> [String: [String: Record]] {
        struct Standing { var maxLoad = -Double.infinity; var bestReps: [Double: Int] = [:]; var any = false }
        var standing: [String: Standing] = [:]
        var out: [String: [String: Record]] = [:]
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            for entry in session.exercises {
                let key = MuscleMap.canonical(entry.name)
                var s = standing[key] ?? Standing()
                for set in entry.sets {
                    let mine = load(of: set)
                    if s.any {
                        var record: Record?
                        if mine > s.maxLoad { record = .load }
                        else if let best = s.bestReps[mine], set.reps > best { record = .reps }
                        if let record, out[session.dateString, default: [:]][key] != .load {
                            out[session.dateString, default: [:]][key] = record
                        }
                    }
                    s.any = true
                    s.maxLoad = max(s.maxLoad, mine)
                    s.bestReps[mine] = max(s.bestReps[mine] ?? 0, set.reps)
                }
                standing[key] = s
            }
        }
        return out
    }

    /// Change from the earliest point (long-term). `sinceDays` limits the
    /// window (short-term), counted back from `now` — not from the last
    /// session, so a lift left in June doesn't report a change "in the last
    /// three weeks" in September. Nil when fewer than two points fall inside.
    static func change(_ series: [TrendPoint], sinceDays days: Int? = nil,
                       now: Date = Date(), calendar: Calendar = .current) -> TrendChange? {
        guard let last = series.last, series.count >= 2 else { return nil }
        let start: TrendPoint?
        if let days {
            let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
            guard last.date >= cutoff else { return nil }
            start = series.first { $0.date >= cutoff }
        } else {
            start = series.first
        }
        guard let s = start, s.date < last.date else { return nil }
        let delta = last.value - s.value
        return TrendChange(delta: delta, percent: s.value == 0 ? nil : delta / s.value * 100)
    }

    // MARK: - Every lift at a glance

    /// One lift's standing: what was done last and when, the best set ever
    /// and the day it was first hit, how often lately. The same facts the
    /// coach's digest states — computed once, drawn and told alike.
    struct LiftSummary: Identifiable, Equatable {
        var id: String { key }
        /// The canonical name; `name` is the spelling the log used last.
        let key: String
        let name: String
        let last: Date
        let lastTokens: String
        /// The best set: heaviest load, then most reps at it; bodyweight
        /// lifts compare added load the same way.
        let best: WorkSet?
        /// The day the standing best was first lifted — "days since a PR"
        /// counts from here.
        let bestDate: Date?
        let sessionsInFourWeeks: Int
        let sessionsEver: Int
        /// Where the lift came in its last session, for a stable order.
        let order: Int

        func daysSinceLast(today: Date, calendar: Calendar) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: today)).day ?? 0
        }

        func daysSinceBest(today: Date, calendar: Calendar) -> Int? {
            bestDate.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: today)).day ?? 0 }
        }
    }

    /// Every lift in the log, most recently done first; lifts from the same
    /// day in the order they were done. Lines dated after `today` are ignored.
    static func liftSummaries(in sessions: [Session], today: Date = Date(),
                              calendar: Calendar = .current) -> [LiftSummary] {
        struct Row {
            var name: String; var last: Session; var lastTokens: String; var order: Int
            var best: WorkSet?; var bestDate: Date?
            var inFourWeeks: Int; var ever: Int
        }
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: today)) ?? today
        var rows: [String: Row] = [:]
        for session in sessions.sorted(by: { $0.date < $1.date }) where session.date <= today {
            var seenToday = Set<String>()
            for (i, entry) in session.exercises.enumerated() {
                let key = MuscleMap.canonical(entry.name)
                var row = rows[key] ?? Row(name: entry.name, last: session, lastTokens: "", order: i,
                                           best: nil, bestDate: nil, inFourWeeks: 0, ever: 0)
                // A second line for the lift the same day is the same session.
                if seenToday.insert(key).inserted {
                    row.ever += 1
                    if session.date >= fourWeeksAgo { row.inFourWeeks += 1 }
                    row.lastTokens = ""
                }
                row.name = entry.name
                row.last = session
                row.order = i
                row.lastTokens = (row.lastTokens.isEmpty ? "" : row.lastTokens + " ") + entry.sets.map(\.token).joined(separator: " ")
                for set in entry.sets {
                    let beats: Bool
                    if let best = row.best {
                        beats = load(of: set) > load(of: best) || (load(of: set) == load(of: best) && set.reps > best.reps)
                    } else {
                        beats = true
                    }
                    if beats { row.best = set; row.bestDate = session.date }
                }
                rows[key] = row
            }
        }
        return rows.map { key, row in
            LiftSummary(key: key, name: row.name, last: row.last.date, lastTokens: row.lastTokens,
                        best: row.best, bestDate: row.bestDate,
                        sessionsInFourWeeks: row.inFourWeeks, sessionsEver: row.ever, order: row.order)
        }
        .sorted { $0.last != $1.last ? $0.last > $1.last : $0.order < $1.order }
    }
}

private extension Array where Element == TrendPoint {
    /// Mark each point that beats every point before it. The first point is
    /// a start, not a record.
    func flagged() -> [TrendPoint] {
        var best = -Double.infinity
        return enumerated().map { i, point in
            var p = point
            p.isRecord = i > 0 && point.value > best
            best = Swift.max(best, point.value)
            return p
        }
    }
}
