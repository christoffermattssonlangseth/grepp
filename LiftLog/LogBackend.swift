import Foundation

/// Where a file lives. The log and its brief files are read and written
/// through this and nothing else, so the app is the same app whether the
/// file is in a GitHub repo or in iCloud Drive.
///
/// Two operations, both whole-file: read what's there with a version token,
/// and write with the token from the last read so a stale write is refused
/// rather than clobbering. GitHub's token is the blob sha; iCloud's is the
/// modification date. Every write is still a merge on the freshest content —
/// the safety that matters is in `Store.push`, above this layer.
protocol LogBackend {
    /// The file's content and version, or nil when it doesn't exist yet.
    func fetch() async throws -> LogFile?
    /// Create (nil version) or replace (the version last read). Returns the new
    /// version when the backend reports one.
    @discardableResult
    func put(content: String, version: String?, message: String) async throws -> String?
}

struct LogFile {
    var content: String
    var version: String
}

extension GitHubService: LogBackend {
    func fetch() async throws -> LogFile? {
        guard let state: FileState = try await fetch() else { return nil }
        return LogFile(content: state.content, version: state.sha)
    }

    func put(content: String, version: String?, message: String) async throws -> String? {
        try await put(content: content, sha: version, message: message)
    }
}
