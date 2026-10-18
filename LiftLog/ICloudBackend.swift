import Foundation

/// The log as a file in iCloud Drive: `Grepp/training.md`, visible in the
/// Files app, synced by Apple, no account with anyone but Apple.
///
/// Reads and writes go through a file coordinator so they don't collide with
/// iCloud's own sync, and a read of a file that's only a placeholder on this
/// device waits for the download rather than reading nothing. The version
/// token is the modification date; a write with an older one is refused, the
/// same contract GitHub's sha gives.
nonisolated struct ICloudBackend: LogBackend {
    /// Path within the app's iCloud Documents folder — "training.md".
    var path: String

    enum ICloudError: LocalizedError {
        case unavailable, stale
        /// The file is in iCloud but not on this phone yet. Nothing is
        /// written until it is: a write now would start a second log.
        case notReady
        /// The file's bytes aren't UTF-8 text.
        case notText
        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "iCloud Drive isn't available. Sign in to iCloud on this phone and turn on iCloud Drive for Grepp in Settings ▸ Apple Account ▸ iCloud."
            case .stale:
                return "The file changed on another device. Reloading and trying again."
            case .notReady:
                return "iCloud is still downloading the log to this phone. Saves wait until it's here."
            case .notText:
                return "The log in iCloud isn't UTF-8 text, so it wasn't read and nothing will be saved over it. Re-save it as UTF-8."
            }
        }
    }

    /// Whether this phone is signed in to iCloud at all. Cheap; no I/O. Can
    /// say no on a Simulator that is signed in — `available()` is the real test.
    static var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// The check that matters: can the app's container be resolved. True when
    /// the device is signed in, iCloud Drive is on for the app, and the build
    /// carries the entitlement. Touches the disk, so it's async.
    static func available() async -> Bool {
        await documents() != nil
    }

    /// The Documents folder of the app's container. Resolving it can touch the
    /// disk, so it's done off the main thread.
    private static func documents() async -> URL? {
        await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents", isDirectory: true)
        }.value
    }

    private func fileURL() async throws -> URL {
        guard let documents = await Self.documents() else { throw ICloudError.unavailable }
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return documents.appendingPathComponent(clean)
    }

    func fetch() async throws -> LogFile? {
        let url = try await fileURL()
        let result = try await Task.detached(priority: .userInitiated) { () throws -> LogFile? in
            let fm = FileManager.default
            // A placeholder for a file that lives on another device: ask for it.
            // The coordinated read below then waits until it's here.
            try? fm.startDownloadingUbiquitousItem(at: url)
            var result: LogFile?
            var failure: Error?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                guard fm.fileExists(atPath: readURL.path) else { return }
                do {
                    let data = try Data(contentsOf: readURL)
                    // Bytes that aren't text are not read as some other text:
                    // written back, the replacement characters would stick.
                    guard var content = String(data: data, encoding: .utf8) else {
                        failure = ICloudError.notText
                        return
                    }
                    // Two devices wrote while apart and iCloud kept both: the
                    // read is both, so neither device's sets are lost. The
                    // version names the conflicts, and the write that carries
                    // this content is what marks them resolved.
                    for conflict in NSFileVersion.unresolvedConflictVersionsOfItem(at: readURL) ?? [] {
                        if let other = (try? Data(contentsOf: conflict.url)).flatMap({ String(data: $0, encoding: .utf8) }) {
                            content = WorkoutParser.union(content, other)
                        }
                    }
                    result = LogFile(content: content, version: Self.version(of: readURL))
                } catch {
                    failure = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let failure { throw failure }
            if result == nil, Self.hasPlaceholder(for: url) { throw ICloudError.notReady }
            return result
        }.value
        if let result { return result }
        // Nothing here — but on a fresh install iCloud may know of the file
        // before this device has so much as a placeholder for it. Answering
        // "no file" then would have the first save create one beside it.
        guard await Self.cloudHasNoCopy(of: url) else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw ICloudError.notReady
        }
        return nil
    }

    func put(content: String, version: String?, message: String) async throws -> String? {
        let url = try await fileURL()
        // A write that creates the file must know there is none in iCloud.
        if version == nil, !FileManager.default.fileExists(atPath: url.path) {
            guard await Self.cloudHasNoCopy(of: url) else { throw ICloudError.notReady }
        }
        return try await Task.detached(priority: .userInitiated) { () throws -> String? in
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var written: String?
            var failure: Error?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
                // Refuse to write over a newer file: another device got there
                // first — or the file has arrived since a read said there was
                // none, which on a fresh install is the whole log syncing down.
                // A conflict that turned up since the read changes the version
                // too, so its lines are read in before anything is written.
                if fm.fileExists(atPath: writeURL.path), version == nil || Self.version(of: writeURL) != version {
                    failure = ICloudError.stale
                    return
                }
                if !fm.fileExists(atPath: writeURL.path), Self.hasPlaceholder(for: writeURL) {
                    failure = ICloudError.notReady
                    return
                }
                do {
                    try Data(content.utf8).write(to: writeURL, options: .atomic)
                    // The content was read with the conflicts merged in, and
                    // the version check says they're the same ones: settled.
                    for conflict in NSFileVersion.unresolvedConflictVersionsOfItem(at: writeURL) ?? [] {
                        conflict.isResolved = true
                    }
                    try? NSFileVersion.removeOtherVersionsOfItem(at: writeURL)
                    written = Self.version(of: writeURL)
                } catch {
                    failure = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let failure { throw failure }
            return written
        }.value
    }

    /// Modification date to the millisecond, as the version token — and, when
    /// iCloud holds unresolved conflict copies, how many and the newest, so a
    /// write can't settle conflicts its content never saw.
    private static func version(of url: URL) -> String {
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
        var token = String(Int64(date.timeIntervalSince1970 * 1000))
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        if !conflicts.isEmpty {
            let newest = conflicts.compactMap(\.modificationDate).max() ?? .distantPast
            token += "+\(conflicts.count)@\(Int64(newest.timeIntervalSince1970 * 1000))"
        }
        return token
    }

    /// The `.name.icloud` stand-in an older iCloud leaves for a file that
    /// hasn't downloaded: the file exists, just not here yet.
    private static func hasPlaceholder(for url: URL) -> Bool {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
    }

    /// Ask iCloud itself whether the file exists anywhere. True only when the
    /// answer is a definite no; a query that doesn't finish counts as "maybe",
    /// which keeps a write from creating a second log.
    @MainActor
    private static func cloudHasNoCopy(of url: URL) async -> Bool {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, url.lastPathComponent)
        // Matched on the path inside Documents: the container's own path can
        // be spelled with or without /private.
        let wanted = url.path.range(of: "/Documents/").map { String(url.path[$0.lowerBound...]) } ?? "/" + url.lastPathComponent
        let found: Bool? = await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
            ) { note in
                guard let query = note.object as? NSMetadataQuery else { return }
                query.disableUpdates()
                let paths = query.results.compactMap {
                    ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL
                }.map(\.path)
                once.finish(paths.contains { $0.hasSuffix(wanted) })
            }
            once.cleanup = {
                query.stop()
                NotificationCenter.default.removeObserver(observer)
            }
            if !query.start() { once.finish(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { once.finish(nil) }
        }
        return found == false
    }

    /// Resumes a continuation exactly once, whichever of the query or the
    /// timeout gets there first. Main thread only.
    private final class Once: @unchecked Sendable {
        private var continuation: CheckedContinuation<Bool?, Never>?
        var cleanup: (() -> Void)?
        init(_ continuation: CheckedContinuation<Bool?, Never>) { self.continuation = continuation }
        func finish(_ value: Bool?) {
            guard let c = continuation else { return }
            continuation = nil
            cleanup?(); cleanup = nil
            c.resume(returning: value)
        }
    }
}
