import Foundation
import SwiftUI
import Combine
import WidgetKit

/// App-wide state: config, the loaded sessions, and sync with GitHub.
///
/// Offline-first: every write goes through a merge-on-remote push, but if the
/// network is unreachable the write is queued locally (`pending`) and the file's
/// last-known content is cached, so the app keeps working in a signal-dead gym
/// and syncs automatically on the next reconnect.
@MainActor
final class Store: ObservableObject {
    /// The one instance. The app's scene owns it as a StateObject, and the
    /// lock-screen intent — which the system performs in this process, scene
    /// or no scene — reaches it here.
    static let shared = Store()

    // Config (token lives in Keychain, everything else in UserDefaults).
    @AppStorage("gh_owner") var owner = ""
    @AppStorage("gh_repo") var repo = ""
    @AppStorage("gh_path") var path = "training.md"
    @AppStorage("gh_branch") var branch = "main"

    /// Optional companion files to `training.md`, in the same repo and branch: how
    /// you want to be coached, and what you're working toward. Together they are the
    /// Coach tab's standing brief. Blank a path, or never create the file, and Coach
    /// just runs on its own defaults.
    @AppStorage("gh_coaching_path") var coachingPath = "coaching.md"
    @AppStorage("gh_goals_path") var goalsPath = "goals.md"
    @AppStorage("gh_research_path") var researchPath = "research.md"

    /// Claude workspace for the Coach tab. An identifier, not a secret, so it sits
    /// in UserDefaults beside the repo config. Only needed when the API key spans
    /// more than one workspace.
    @AppStorage("anthropic_workspace") var anthropicWorkspace = ""

    @Published var token: String = Keychain.get(account: "token") ?? ""

    /// Claude API key for the Coach tab. Also lives in the Keychain, under its own
    /// service — never in UserDefaults, and never in source (this repo is public).
    @Published var anthropicKey: String = CoachCredentials.stored ?? ""

    @Published private(set) var sessions: [Session] = [] {
        didSet { publishWidgetSnapshot() }
    }
    @Published private(set) var fileSHA: String?
    @Published var status: String = ""
    @Published var isBusy = false

    /// Outcome of the last brief-file save. Kept apart from `status`, which is
    /// about the log and its sync: the Log tab shows `status`, and a "Saved
    /// goals.md" from the Coach tab has no business appearing there.
    @Published private(set) var briefStatus: String = ""

    /// Writes that haven't reached GitHub yet, oldest first. Persisted across launches.
    @Published private(set) var pending: [PendingWrite] = []

    /// Contents of `coachingPath` and `goalsPath`, empty when there's no such file.
    /// Cached like the log so they survive a cold start with no signal.
    @Published private(set) var brief = CoachContext.Brief.none

    /// Drives the selected tab so views can jump between them (0 = Log … 4 = Settings).
    @Published var selectedTab = 0

    /// A "edit this past entry" request handed from History to the Log tab. The Log
    /// view consumes it (pre-fills date + exercise) and clears it.
    struct EditRequest: Equatable { var name: String; var date: Date }
    @Published var editRequest: EditRequest?

    /// Send the user to the Log tab pre-filled to edit a specific past exercise.
    func requestEdit(exercise name: String, on date: Date) {
        editRequest = EditRequest(name: name, date: date)
        selectedTab = 0
    }

    /// Prescriptions from Coach handed to the Log tab, in order: exercises and
    /// the sets to do. Log loads the first as a target and advances to the next as
    /// each is finished — a whole session without leaving the tab. Every exercise
    /// still pushes on its own the moment it's done; only the *navigation* is
    /// batched, never the saves.
    @Published var prescriptionRequest: [ExerciseEntry] = []

    func requestLog(_ entries: [ExerciseEntry]) {
        prescriptionRequest = entries
        selectedTab = 0
    }

    /// An "open Your brief" request handed from Settings to the Coach tab, which
    /// consumes it and clears it. Same shape as `editRequest`: the brief is
    /// configured from Settings, but it belongs to Coach, which is where it's used.
    @Published var briefRequest = false

    func requestBrief() {
        briefRequest = true
        selectedTab = 3
    }

    /// The outcome of a `commit`, so callers don't have to sniff `status` text.
    enum CommitResult { case pushed, queued, failed }

    /// The two files that make up the coach's standing brief. One identity for
    /// each, so a screen can read, edit and save either without special-casing.
    enum BriefFile: String, CaseIterable, Identifiable {
        case coaching, goals, research
        var id: String { rawValue }

        var title: String {
            switch self {
            case .coaching: return "How I train"
            case .goals: return "What I'm working toward"
            case .research: return "What the evidence says"
            }
        }

        var hint: String {
            switch self {
            case .coaching:
                return "Philosophy, preferences, the shape of your week, injuries to work around."
            case .goals:
                return "Targets and dates. The coach programmes backwards from these."
            case .research:
                return "One finding per line, tagged [R1], [R2]… The coach cites the tags. Easier to fill from Coach: hand it a paper."
            }
        }
    }

    func path(for file: BriefFile) -> String {
        switch file {
        case .coaching: return coachingPath
        case .goals: return goalsPath
        case .research: return researchPath
        }
    }

    func text(for file: BriefFile) -> String {
        switch file {
        case .coaching: return brief.coaching
        case .goals: return brief.goals
        case .research: return brief.research
        }
    }

    private enum StoreError: LocalizedError {
        case unsafeMerge
        var errorDescription: String? {
            "Aborted: couldn't parse the remote file safely."
        }
    }

    // UserDefaults keys for the offline cache + queue.
    private let cacheKey = "gh_cache"
    private let coachingCacheKey = "gh_coaching_cache"
    private let goalsCacheKey = "gh_goals_cache"
    private let researchCacheKey = "gh_research_cache"
    private let pendingKey = "gh_pending"
    private let draftKey = "session_draft"
    private let plansKey = "plan_records"
    private var defaults: UserDefaults { .standard }

    /// The exercise being logged right now, persisted so a kill mid-session
    /// costs nothing. Nil when there's nothing worth keeping.
    @Published private(set) var draft: SessionDraft?
    /// Bumped when the draft was changed from outside the Log screen (the
    /// lock-screen button), so the screen knows to take it back in.
    @Published private(set) var draftRevision = 0

    /// What Coach prescribed and what became of it, so the next answer can
    /// start from the session as lifted rather than as written.
    @Published private(set) var plans: [PlanRecord] = []

    init() {
        pending = loadPending()
        draft = loadDraft()
        plans = loadPlans()
        brief = CoachContext.Brief(coaching: defaults.string(forKey: coachingCacheKey) ?? "",
                                   goals: defaults.string(forKey: goalsCacheKey) ?? "",
                                   research: defaults.string(forKey: researchCacheKey) ?? "")
        // Show cached content + any queued writes immediately, before the network load.
        sessions = WorkoutParser.applying(pending, to: cachedSessions())
    }

    func saveToken() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        token = trimmed
        if trimmed.isEmpty { Keychain.delete(account: "token") }
        else { Keychain.set(trimmed, account: "token") }
    }

    /// Store (or clear) the Claude API key. Mirrors `saveToken`.
    func saveAnthropicKey() {
        let trimmed = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        anthropicKey = trimmed
        CoachCredentials.store(trimmed)
    }

    private var service: GitHubService {
        GitHubService(owner: owner, repo: repo, path: path, branch: branch, token: token)
    }

    /// Overwrite one of the brief files — hand-edited, or written by the coach in
    /// an interview.
    ///
    /// A whole-file replace of that one path and nothing else: it never touches the
    /// log or the other brief file, and git history means a bad write is a revert
    /// away. Unlike a workout it isn't queued when offline — you're sitting there
    /// looking at it, so a plain failure you can retry beats a silent queue.
    @discardableResult
    func save(_ text: String, to file: BriefFile) async -> CommitResult {
        guard !isBusy else { return .failed }
        let path = self.path(for: file).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            briefStatus = "No \(file.rawValue) file set — add a path in Settings."
            return .failed
        }

        isBusy = true; briefStatus = "Saving \(path)…"
        defer { isBusy = false }

        let remote = GitHubService(owner: owner, repo: repo, path: path, branch: branch, token: token)
        let content = text.hasSuffix("\n") ? text : text + "\n"
        do {
            // Fetch first for the sha: a nil sha creates the file, a stale one is a 409.
            let existing = try await remote.fetch()
            _ = try await remote.put(content: content, sha: existing?.sha, message: "Update \(path) from LiftLog")
            switch file {
            case .coaching: brief.coaching = content
            case .goals: brief.goals = content
            case .research: brief.research = content
            }
            defaults.set(content, forKey: cacheKey(for: file))
            briefStatus = "Saved \(path) ✓"
            return .pushed
        } catch is URLError {
            briefStatus = "Offline — couldn't save \(path). Try again when you have signal."
            return .failed
        } catch {
            briefStatus = error.localizedDescription
            return .failed
        }
    }

    /// Keep a note from the coach: coaching.md with the note appended under the
    /// coach's heading, pushed like any other brief edit.
    func remember(_ note: String) async -> CommitResult {
        await save(CoachContext.appendingNote(note, to: brief.coaching), to: .coaching)
    }

    /// Keep evidence the coach has written: research.md with the entries added
    /// and numbered, pushed like any other brief edit.
    func addResearch(_ entries: String) async -> CommitResult {
        await save(CoachContext.appendingResearch(entries, to: brief.research), to: .research)
    }

    /// The evidence brief, parsed.
    var evidence: [CoachContext.ResearchEntry] { CoachContext.parseResearch(brief.research) }

    private func cacheKey(for file: BriefFile) -> String {
        switch file {
        case .coaching: return coachingCacheKey
        case .goals: return goalsCacheKey
        case .research: return researchCacheKey
        }
    }

    /// Refresh the two companion files. Deliberately cannot fail the load: they're
    /// optional, a 404 just means the file isn't there, and anything else leaves the
    /// cached copy in place — a hiccup fetching your notes must never cost you the
    /// training history.
    private func loadBrief() async {
        brief = CoachContext.Brief(
            coaching: await companion(at: coachingPath, cacheKey: coachingCacheKey) ?? brief.coaching,
            goals: await companion(at: goalsPath, cacheKey: goalsCacheKey) ?? brief.goals,
            research: await companion(at: researchPath, cacheKey: researchCacheKey) ?? brief.research
        )
    }

    /// One companion file from the same repo and branch as the log. Returns nil for
    /// "couldn't reach it, keep what you had"; an empty string means "there is no such
    /// file", which is a real answer and clears any stale cache.
    private func companion(at path: String, cacheKey: String) async -> String? {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let file = GitHubService(owner: owner, repo: repo, path: path, branch: branch, token: token)
        do {
            // fetch() answers nil for a 404 — the file simply isn't there, which is a
            // real answer and clears any stale cache. `try?` can't express that: it
            // flattens, so a dead connection would read as "no such file" and quietly
            // blank the brief.
            let content = try await file.fetch()?.content ?? ""
            defaults.set(content, forKey: cacheKey)
            return content
        } catch {
            return nil   // couldn't reach it — keep whatever we had
        }
    }

    /// Unique exercise names seen in history, for the picker (most recent first).
    var knownExercises: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in sessions.sorted(by: { $0.date > $1.date }) {
            for ex in session.exercises where !seen.contains(ex.name.lowercased()) {
                seen.insert(ex.name.lowercased())
                result.append(ex.name)
            }
        }
        return result
    }

    /// Hand the home screen widget the latest session. Only when it changed:
    /// a reload per parse would be noise, and sessions re-parse on every load.
    private func publishWidgetSnapshot() {
        let snapshot = sessions.max(by: { $0.date < $1.date }).map { last in
            WidgetSnapshot(day: last.dateString, lines: last.exercises.map {
                WidgetSnapshot.Line(name: $0.name, sets: $0.sets.map(\.token).joined(separator: " "))
            })
        }
        guard snapshot != WidgetSnapshot.load() else { return }
        WidgetSnapshot.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
    }

    // MARK: - Load

    func load() async {
        guard !isBusy else { return }   // don't overlap with an in-flight save/load
        isBusy = true; status = "Loading…"
        defer { isBusy = false }
        do {
            if let state = try await service.fetch() {
                cacheContent(state.content)
                fileSHA = state.sha
                // Show queued-but-unsynced writes layered on top of the fresh remote.
                sessions = WorkoutParser.applying(pending, to: WorkoutParser.parse(state.content))
                status = "Loaded \(sessions.count) sessions.\(pendingSuffix)"
            } else {
                cacheContent("")
                fileSHA = nil
                sessions = WorkoutParser.applying(pending, to: [])
                status = "No file yet — first save will create it.\(pendingSuffix)"
            }
            await loadBrief()
            await flushPending()
        } catch is URLError {
            // Offline: fall back to the cache so the app still shows history.
            sessions = WorkoutParser.applying(pending, to: cachedSessions())
            status = "Offline — showing cached data.\(pendingSuffix)"
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: - Commit

    /// Add/replace an exercise entry by merging it into the CURRENT remote file,
    /// never by overwriting with stale in-memory state. If the network is down the
    /// write is queued locally and applied optimistically, then flushed on reconnect.
    @discardableResult
    func commit(_ entry: ExerciseEntry, on date: Date, message: String) async -> CommitResult {
        await perform(PendingWrite(entry: entry, date: date, message: message))
    }

    /// Remove an exercise from a day's session. Same offline-safe path as `commit`.
    @discardableResult
    func delete(exercise name: String, on date: Date, message: String) async -> CommitResult {
        await perform(PendingWrite(operation: .delete(name: name), date: date, message: message))
    }

    /// Push a single change (add/replace or delete) via merge-on-remote, or queue it
    /// locally when offline. Shared by `commit` and `delete`.
    @discardableResult
    private func perform(_ write: PendingWrite) async -> CommitResult {
        guard !isBusy else { return .failed }
        isBusy = true; status = "Saving…"
        defer { isBusy = false }

        do {
            let base = try await push(write)
            cacheContent(WorkoutParser.serialize(base))
            // A successful reach means we can drain anything queued earlier, too.
            await flushPending()
            sessions = WorkoutParser.applying(pending, to: base)
            status = pending.isEmpty ? "Pushed ✓" : "Pushed ✓ — \(pending.count) still queued"
            return .pushed
        } catch is URLError {
            enqueue(write)
            status = "Offline — saved locally, will sync (\(pending.count) queued)"
            return .queued
        } catch {
            status = error.localizedDescription
            return .failed
        }
    }

    /// Fetch the current remote file, apply one write to it, and push. Retries on
    /// GitHub 409 conflicts (a briefly-stale SHA after a recent write). Returns the
    /// updated sessions on success; throws `URLError` when offline so the caller can queue.
    private func push(_ write: PendingWrite) async throws -> [Session] {
        let maxAttempts = 4
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let remote = try await service.fetch()
                var base = remote.map { WorkoutParser.parse($0.content) } ?? []

                // Safety net: refuse to act on a non-trivial file we couldn't parse.
                let existingLines = remote?.content
                    .split(separator: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .count ?? 0
                if existingLines > 1 && base.isEmpty { throw StoreError.unsafeMerge }

                WorkoutParser.apply(write, to: &base)

                let content = WorkoutParser.serialize(base)
                fileSHA = try await service.put(content: content, sha: remote?.sha, message: write.message)
                return base
            } catch let error as GitHubService.GitHubError {
                if case .badResponse(409, _) = error, attempt < maxAttempts {
                    status = "Syncing… (retry \(attempt))"
                    try? await Task.sleep(nanoseconds: 700_000_000)  // 0.7s back-off
                    lastError = error
                    continue
                }
                throw error
            }
        }
        throw lastError ?? StoreError.unsafeMerge
    }

    /// Replay queued writes against the current remote, oldest first. Stops (keeping
    /// the rest queued) as soon as one can't be delivered — offline again, or a
    /// permanent error the user needs to fix (e.g. a bad token).
    func flushPending() async {
        while let write = pending.first {
            do {
                let base = try await push(write)
                cacheContent(WorkoutParser.serialize(base))
                pending.removeFirst()
                savePending()
            } catch is URLError {
                return   // still offline — leave the queue intact
            } catch {
                status = "Sync paused — \(error.localizedDescription)"
                return
            }
        }
    }

    private func enqueue(_ write: PendingWrite) {
        pending.append(write)
        savePending()
        // Optimistically reflect the write in the UI right away.
        sessions = WorkoutParser.applying(pending, to: cachedSessions())
    }

    // MARK: - History suggestions

    func lastEntry(for name: String, before date: Date) -> ExerciseEntry? {
        WorkoutParser.lastEntry(for: name, in: sessions, before: date)
    }

    // MARK: - Local persistence (cache + queue)

    private var pendingSuffix: String { pending.isEmpty ? "" : " · \(pending.count) queued offline" }

    private func cacheContent(_ content: String) { defaults.set(content, forKey: cacheKey) }
    private func cachedSessions() -> [Session] {
        WorkoutParser.parse(defaults.string(forKey: cacheKey) ?? "")
    }

    /// A prescription was loaded into the Log tab.
    func recordPlan(_ entries: [ExerciseEntry], on date: Date) {
        plans.prescribe(entries, on: date)
        savePlans()
    }

    /// A planned lift was finished under `date`.
    func completePlan(_ entry: ExerciseEntry, on date: Date) {
        plans.complete(entry, on: date)
        savePlans()
    }

    private func savePlans() {
        plans.prune(before: Date().addingTimeInterval(-30 * 86_400))
        defaults.set(try? JSONEncoder().encode(plans), forKey: plansKey)
    }
    private func loadPlans() -> [PlanRecord] {
        guard let data = defaults.data(forKey: plansKey),
              let decoded = try? JSONDecoder().decode([PlanRecord].self, from: data) else { return [] }
        return decoded
    }

    /// The lock-screen button: land the next planned set, or the last one
    /// again, and restart the rest — straight into the persisted draft, since
    /// the Log screen may not exist when the system wakes us for this.
    func sameAgain() {
        guard var d = draft, let set = d.sameAgainSet else { return }
        d.sets.append(WorkSet(weight: set.weight, added: set.added, reps: set.reps))
        d.restStart = Date()
        saveDraft(d)
        draftRevision += 1
        RestSignals.sync(d)
    }

    func saveDraft(_ new: SessionDraft?) {
        draft = new
        if let new {
            defaults.set(try? JSONEncoder().encode(new), forKey: draftKey)
        } else {
            defaults.removeObject(forKey: draftKey)
        }
    }
    private func loadDraft() -> SessionDraft? {
        guard let data = defaults.data(forKey: draftKey) else { return nil }
        return try? JSONDecoder().decode(SessionDraft.self, from: data)
    }

    private func savePending() {
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingKey)
    }
    private func loadPending() -> [PendingWrite] {
        guard let data = defaults.data(forKey: pendingKey),
              let decoded = try? JSONDecoder().decode([PendingWrite].self, from: data) else { return [] }
        return decoded
    }
}
