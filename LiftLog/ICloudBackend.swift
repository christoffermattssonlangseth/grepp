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
        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "iCloud Drive isn't available. Sign in to iCloud on this phone and turn on iCloud Drive for Grepp in Settings ▸ Apple Account ▸ iCloud."
            case .stale:
                return "The file changed on another device. Reloading and trying again."
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
        if isAvailable { return true }
        return await documents() != nil
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
        return try await Task.detached(priority: .userInitiated) { () throws -> LogFile? in
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
                    let content = String(decoding: data, as: UTF8.self)
                    result = LogFile(content: content, version: Self.version(of: readURL))
                } catch {
                    failure = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let failure { throw failure }
            return result
        }.value
    }

    func put(content: String, version: String?, message: String) async throws -> String? {
        let url = try await fileURL()
        return try await Task.detached(priority: .userInitiated) { () throws -> String? in
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var written: String?
            var failure: Error?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
                // Refuse to write over a newer file: another device got there first.
                if let version, fm.fileExists(atPath: writeURL.path), Self.version(of: writeURL) != version {
                    failure = ICloudError.stale
                    return
                }
                do {
                    try Data(content.utf8).write(to: writeURL, options: .atomic)
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

    /// Modification date to the millisecond, as the version token.
    private static func version(of url: URL) -> String {
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
        return String(Int64(date.timeIntervalSince1970 * 1000))
    }
}
