import Foundation
import SwiftUI
import Combine

/// App-wide state: config, the loaded sessions, and sync with GitHub.
///
/// Offline-first: every write goes through a merge-on-remote push, but if the
/// network is unreachable the write is queued locally (`pending`) and the file's
/// last-known content is cached, so the app keeps working in a signal-dead gym
/// and syncs automatically on the next reconnect.
@MainActor
final class Store: ObservableObject {
    // Config (token lives in Keychain, everything else in UserDefaults).
    @AppStorage("gh_owner") var owner = ""
    @AppStorage("gh_repo") var repo = ""
    @AppStorage("gh_path") var path = "training.md"
    @AppStorage("gh_branch") var branch = "main"

    /// Optional companion file to `training.md`, in the same repo and branch: the
    /// lifter's own coaching notes, handed to the Coach tab as a standing brief.
    /// Blank, or a file that isn't there, and Coach just runs on its own defaults.
    @AppStorage("gh_coaching_path") var coachingPath = "coaching.md"

    /// Claude workspace for the Coach tab. An identifier, not a secret, so it sits
    /// in UserDefaults beside the repo config. Only needed when the API key spans
    /// more than one workspace.
    @AppStorage("anthropic_workspace") var anthropicWorkspace = ""

    @Published var token: String = Keychain.get(account: "token") ?? ""

    /// Claude API key for the Coach tab. Also lives in the Keychain, under its own
    /// service — never in UserDefaults, and never in source (this repo is public).
    @Published var anthropicKey: String = CoachCredentials.stored ?? ""

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var fileSHA: String?
    @Published var status: String = ""
    @Published var isBusy = false

    /// Writes that haven't reached GitHub yet, oldest first. Persisted across launches.
    @Published private(set) var pending: [PendingWrite] = []

    /// Contents of `coachingPath`, or empty when there's no such file. Cached like
    /// the log so it survives a cold start with no signal.
    @Published private(set) var coachingGuide = ""

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

    /// The outcome of a `commit`, so callers don't have to sniff `status` text.
    enum CommitResult { case pushed, queued, failed }

    private enum StoreError: LocalizedError {
        case unsafeMerge
        var errorDescription: String? {
            "Aborted: couldn't parse the remote file safely."
        }
    }

    // UserDefaults keys for the offline cache + queue.
    private let cacheKey = "gh_cache"
    private let coachingCacheKey = "gh_coaching_cache"
    private let pendingKey = "gh_pending"
    private var defaults: UserDefaults { .standard }

    init() {
        pending = loadPending()
        coachingGuide = defaults.string(forKey: coachingCacheKey) ?? ""
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

    /// Same repo and branch as the log, different file.
    private var coachingService: GitHubService {
        GitHubService(owner: owner, repo: repo, path: coachingPath, branch: branch, token: token)
    }

    /// Refresh the coaching notes. Deliberately cannot fail the load: the file is
    /// optional, a 404 just means there isn't one, and anything else falls back to
    /// the cached copy so a hiccup here never costs you the training history.
    private func loadCoachingGuide() async {
        guard !coachingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            coachingGuide = ""
            return
        }
        if let state = try? await coachingService.fetch() {
            coachingGuide = state?.content ?? ""
            defaults.set(coachingGuide, forKey: coachingCacheKey)
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
            await loadCoachingGuide()
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

    private func savePending() {
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingKey)
    }
    private func loadPending() -> [PendingWrite] {
        guard let data = defaults.data(forKey: pendingKey),
              let decoded = try? JSONDecoder().decode([PendingWrite].self, from: data) else { return [] }
        return decoded
    }
}
