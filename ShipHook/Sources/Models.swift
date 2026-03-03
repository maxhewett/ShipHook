import Foundation

struct AppConfiguration: Codable {
    var pollIntervalSeconds: TimeInterval
    var githubTokenEnvVar: String?
    var repositories: [RepositoryConfiguration]

    static let `default` = AppConfiguration(
        pollIntervalSeconds: 300,
        githubTokenEnvVar: "GITHUB_TOKEN",
        repositories: []
    )
}

struct RepositoryConfiguration: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var owner: String
    var repo: String
    var branch: String
    var localCheckoutPath: String
    var workingDirectory: String?
    var buildOnFirstSeen: Bool
    var buildMode: BuildMode
    var xcode: XcodeBuildConfiguration?
    var shell: ShellBuildConfiguration?
    var publishCommand: String
    var releaseNotesPath: String?
    var githubTokenEnvVar: String?
    var environment: [String: String]
    var versionStrategy: VersionStrategy

    enum BuildMode: String, Codable {
        case xcodeArchive
        case shell
    }

    enum VersionStrategy: String, Codable {
        case shortSHA
        case shortSHATimestamp
        case dateAndShortSHA
    }
}

struct XcodeBuildConfiguration: Codable, Hashable {
    var projectPath: String?
    var workspacePath: String?
    var scheme: String
    var configuration: String
    var archivePath: String
    var exportPath: String
    var exportOptionsPlistPath: String
    var artifactPath: String
}

struct ShellBuildConfiguration: Codable, Hashable {
    var command: String
    var artifactPath: String
}

struct GitHubBranchSnapshot: Equatable {
    var sha: String
    var committedAt: Date?
    var message: String
    var htmlURL: URL?
}

enum RepositoryActivity: String {
    case idle
    case polling
    case building
    case succeeded
    case failed
}

struct RepositoryRuntimeState: Identifiable {
    var id: String
    var lastSeenSHA: String?
    var lastBuiltSHA: String?
    var lastCheckDate: Date?
    var lastSuccessDate: Date?
    var activity: RepositoryActivity
    var summary: String
    var lastLog: String
    var lastError: String?

    static func initial(id: String) -> RepositoryRuntimeState {
        RepositoryRuntimeState(
            id: id,
            lastSeenSHA: nil,
            lastBuiltSHA: nil,
            lastCheckDate: nil,
            lastSuccessDate: nil,
            activity: .idle,
            summary: "Waiting for first poll",
            lastLog: "",
            lastError: nil
        )
    }
}
