import Foundation

enum GitHubAPIError: LocalizedError {
    case invalidResponse
    case unexpectedStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .unexpectedStatus(code, message):
            return "GitHub returned HTTP \(code): \(message)"
        }
    }
}

struct GitHubReleaseSummary: Identifiable, Equatable, Hashable {
    struct Author: Equatable, Hashable {
        var login: String
        var avatarURL: URL?
        var profileURL: URL?
    }

    var id: Int
    var tagName: String
    var name: String
    var body: String
    var isPrerelease: Bool
    var publishedAt: Date?
    var htmlURL: URL?
    var author: Author?

    var isBeta: Bool {
        isPrerelease || tagName.lowercased().hasSuffix("-beta")
    }

    var versionLabel: String {
        var version = tagName
        if version.lowercased().hasPrefix("v") {
            version.removeFirst()
        }
        if version.lowercased().hasSuffix("-beta") {
            version = String(version.dropLast("-beta".count))
        }
        return version
    }
}

struct GitHubAPI {
    private let session: URLSession = .shared

    func latestBranchSnapshot(
        owner: String,
        repo: String,
        branch: String,
        token: String?
    ) async throws -> GitHubBranchSnapshot {
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F")
        guard let encodedBranch else {
            throw GitHubAPIError.invalidResponse
        }

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/branches/\(encodedBranch)")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ShipHook", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubAPIError.unexpectedStatus(http.statusCode, message)
        }

        let payload = try JSONDecoder.github.decode(BranchResponse.self, from: data)
        return GitHubBranchSnapshot(
            sha: payload.commit.sha,
            committedAt: payload.commit.commit.author.date,
            message: payload.commit.commit.message,
            htmlURL: URL(string: payload.commit.htmlURL),
            authorLogin: payload.commit.author?.login,
            authorAvatarURL: URL(string: payload.commit.author?.avatarURL ?? ""),
            authorProfileURL: URL(string: payload.commit.author?.htmlURL ?? "")
        )
    }

    func listReleases(
        owner: String,
        repo: String,
        token: String?,
        perPage: Int = 20
    ) async throws -> [GitHubReleaseSummary] {
        let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
        let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let url = URL(string: "https://api.github.com/repos/\(encodedOwner)/\(encodedRepo)/releases?per_page=\(max(1, min(perPage, 100)))")!
        var request = makeRequest(url: url, token: token)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validateResponse(data: data, response: response)
        let payload = try JSONDecoder.github.decode([ReleaseResponse].self, from: data)
        return payload.map { release in
            GitHubReleaseSummary(
                id: release.id,
                tagName: release.tagName,
                name: release.name ?? release.tagName,
                body: release.body ?? "",
                isPrerelease: release.prerelease,
                publishedAt: release.publishedAt,
                htmlURL: URL(string: release.htmlURL),
                author: release.author.map {
                    GitHubReleaseSummary.Author(
                        login: $0.login,
                        avatarURL: URL(string: $0.avatarURL),
                        profileURL: URL(string: $0.htmlURL)
                    )
                }
            )
        }
    }

    func deleteRelease(
        owner: String,
        repo: String,
        releaseID: Int,
        token: String?
    ) async throws {
        let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
        let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let url = URL(string: "https://api.github.com/repos/\(encodedOwner)/\(encodedRepo)/releases/\(releaseID)")!
        var request = makeRequest(url: url, token: token)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        try validateResponse(data: data, response: response, acceptedCodes: [204])
    }

    func deleteTagReference(
        owner: String,
        repo: String,
        tagName: String,
        token: String?
    ) async throws {
        let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner
        let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let encodedTag = tagName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F") ?? tagName
        let url = URL(string: "https://api.github.com/repos/\(encodedOwner)/\(encodedRepo)/git/refs/tags/\(encodedTag)")!
        var request = makeRequest(url: url, token: token)
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }
        if http.statusCode == 404 {
            return
        }
        try validateResponse(data: data, response: response, acceptedCodes: [204])
    }

    private func makeRequest(url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ShipHook", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validateResponse(
        data: Data,
        response: URLResponse,
        acceptedCodes: Set<Int> = Set(200..<300)
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        guard acceptedCodes.contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubAPIError.unexpectedStatus(http.statusCode, message)
        }
    }
}

private extension JSONDecoder {
    static var github: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct BranchResponse: Decodable {
    struct CommitNode: Decodable {
        struct User: Decodable {
            var login: String
            var avatarURL: String
            var htmlURL: String

            enum CodingKeys: String, CodingKey {
                case login
                case avatarURL = "avatar_url"
                case htmlURL = "html_url"
            }
        }

        struct CommitDetails: Decodable {
            struct Author: Decodable {
                var date: Date
            }

            var message: String
            var author: Author
        }

        var sha: String
        var htmlURL: String
        var commit: CommitDetails
        var author: User?

        enum CodingKeys: String, CodingKey {
            case sha
            case htmlURL = "html_url"
            case commit
            case author
        }
    }

    var commit: CommitNode
}

private struct ReleaseResponse: Decodable {
    struct Author: Decodable {
        var login: String
        var avatarURL: String
        var htmlURL: String

        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
            case htmlURL = "html_url"
        }
    }

    var id: Int
    var tagName: String
    var name: String?
    var body: String?
    var prerelease: Bool
    var publishedAt: Date?
    var htmlURL: String
    var author: Author?

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case prerelease
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case author
    }
}
