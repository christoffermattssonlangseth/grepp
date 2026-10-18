import Foundation

/// Talks to the GitHub Contents API to read and update a single file
/// (your training.md). Uses a fine-grained personal access token with
/// "Contents: Read and write" permission on the one repo.
struct GitHubService {
    var owner: String
    var repo: String
    var path: String
    var branch: String
    var token: String

    struct FileState {
        var content: String
        var sha: String
    }

    enum GitHubError: LocalizedError {
        case badResponse(Int, String)
        case notHTTP
        case missingConfig
        case decoding
        /// The file's bytes aren't UTF-8 text. Read as empty, the next save
        /// would have replaced the whole log with one line.
        case notText(String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code, let body): return "GitHub \(code): \(body)"
            case .notHTTP: return "Unexpected non-HTTP response from GitHub."
            case .missingConfig: return "Fill in owner, repo, path and token in Settings."
            case .decoding: return "Couldn't read GitHub's response."
            case .notText(let path): return "\(path) on GitHub isn't UTF-8 text, so it wasn't read and nothing will be saved over it. Re-save it as UTF-8."
            }
        }
    }

    private var contentsURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)")!
    }

    private func authorized(_ request: inout URLRequest) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    }

    func validated() throws {
        guard !owner.isEmpty, !repo.isEmpty, !path.isEmpty, !token.isEmpty else {
            throw GitHubError.missingConfig
        }
    }

    /// Fetch current file content + sha. Returns nil content only if file is missing (404).
    func fetch() async throws -> FileState? {
        try validated()
        var comps = URLComponents(url: contentsURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "ref", value: branch)]
        var request = URLRequest(url: comps.url!)
        authorized(&request)
        // Never serve a stale SHA from cache — that causes 409 conflicts on the next PUT.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.notHTTP }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = json["sha"] as? String else {
            throw GitHubError.decoding
        }
        // Never read an unreadable file as an empty one: a save merges onto
        // what was read, and onto "" it writes a log of one line.
        let size = json["size"] as? Int ?? 0
        let base64 = (json["content"] as? String ?? "").replacingOccurrences(of: "\n", with: "")
        let bytes: Data
        if base64.isEmpty && size > 0 {
            // Over 1 MB the contents API sends no content; the blob has it.
            bytes = try await blob(sha)
        } else {
            guard let decoded = Data(base64Encoded: base64) else { throw GitHubError.decoding }
            bytes = decoded
        }
        guard size == 0 || bytes.count == size else { throw GitHubError.decoding }
        guard let content = String(data: bytes, encoding: .utf8) else { throw GitHubError.notText(path) }
        return FileState(content: content, sha: sha)
    }

    /// A file's raw bytes by its blob sha, for a file too big for the contents API.
    private func blob(_ sha: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/blobs/\(sha)")!)
        authorized(&request)
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.notHTTP }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Create or update the file. Pass the sha from a prior fetch to update; nil to
    /// create. Returns the file's *new* blob sha from the response, so callers can
    /// track current state without an extra fetch.
    @discardableResult
    func put(content: String, sha: String?, message: String) async throws -> String? {
        try validated()
        var request = URLRequest(url: contentsURL)
        request.httpMethod = "PUT"
        authorized(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString(),
            "branch": branch,
        ]
        if let sha { body["sha"] = sha }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.notHTTP }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.badResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        // Response shape: { "content": { "sha": "…" }, … }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let contentObj = json?["content"] as? [String: Any]
        return contentObj?["sha"] as? String
    }
}
