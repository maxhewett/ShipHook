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

struct GitHubAPI {
    private let session: URLSession = .shared

    func latestBranchSnapshot(
        owner: String,
        repo: String,
        branch: String,
        token: String?
    ) async throws -> GitHubBranchSnapshot {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/branches/\(branch)")!
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
            htmlURL: URL(string: payload.commit.htmlURL)
        )
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

        enum CodingKeys: String, CodingKey {
            case sha
            case htmlURL = "html_url"
            case commit
        }
    }

    var commit: CommitNode
}
