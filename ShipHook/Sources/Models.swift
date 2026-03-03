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

    var containsOnlyPlaceholderRepository: Bool {
        repositories.count == 1 && repositories[0].isPlaceholderExample
    }
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
    var sparkle: SparkleConfiguration?
    var signing: SigningConfiguration?

    enum BuildMode: String, Codable {
        case xcodeArchive
        case shell
    }

    enum VersionStrategy: String, Codable {
        case shortSHA
        case shortSHATimestamp
        case dateAndShortSHA
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case owner
        case repo
        case branch
        case localCheckoutPath
        case workingDirectory
        case buildOnFirstSeen
        case buildMode
        case xcode
        case shell
        case publishCommand
        case releaseNotesPath
        case githubTokenEnvVar
        case environment
        case versionStrategy
        case sparkle
        case signing
    }

    init(
        id: String,
        name: String,
        owner: String,
        repo: String,
        branch: String,
        localCheckoutPath: String,
        workingDirectory: String?,
        buildOnFirstSeen: Bool,
        buildMode: BuildMode,
        xcode: XcodeBuildConfiguration?,
        shell: ShellBuildConfiguration?,
        publishCommand: String,
        releaseNotesPath: String?,
        githubTokenEnvVar: String?,
        environment: [String: String],
        versionStrategy: VersionStrategy,
        sparkle: SparkleConfiguration?,
        signing: SigningConfiguration?
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.localCheckoutPath = localCheckoutPath
        self.workingDirectory = workingDirectory
        self.buildOnFirstSeen = buildOnFirstSeen
        self.buildMode = buildMode
        self.xcode = xcode
        self.shell = shell
        self.publishCommand = publishCommand
        self.releaseNotesPath = releaseNotesPath
        self.githubTokenEnvVar = githubTokenEnvVar
        self.environment = environment
        self.versionStrategy = versionStrategy
        self.sparkle = sparkle
        self.signing = signing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
        repo = try container.decodeIfPresent(String.self, forKey: .repo) ?? ""
        branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? "main"
        localCheckoutPath = try container.decodeIfPresent(String.self, forKey: .localCheckoutPath) ?? ""
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        buildOnFirstSeen = try container.decodeIfPresent(Bool.self, forKey: .buildOnFirstSeen) ?? false
        buildMode = try container.decodeIfPresent(BuildMode.self, forKey: .buildMode) ?? .xcodeArchive
        xcode = try container.decodeIfPresent(XcodeBuildConfiguration.self, forKey: .xcode)
        shell = try container.decodeIfPresent(ShellBuildConfiguration.self, forKey: .shell)
        publishCommand = try container.decodeIfPresent(String.self, forKey: .publishCommand) ?? ""
        releaseNotesPath = try container.decodeIfPresent(String.self, forKey: .releaseNotesPath)
        githubTokenEnvVar = try container.decodeIfPresent(String.self, forKey: .githubTokenEnvVar)
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        versionStrategy = try container.decodeIfPresent(VersionStrategy.self, forKey: .versionStrategy) ?? .shortSHATimestamp
        sparkle = try container.decodeIfPresent(SparkleConfiguration.self, forKey: .sparkle)
        signing = try container.decodeIfPresent(SigningConfiguration.self, forKey: .signing)
    }

    static func blank() -> RepositoryConfiguration {
        RepositoryConfiguration(
            id: "repo-\(UUID().uuidString.prefix(8).lowercased())",
            name: "New Repository",
            owner: "",
            repo: "",
            branch: "main",
            localCheckoutPath: "",
            workingDirectory: nil,
            buildOnFirstSeen: false,
            buildMode: .xcodeArchive,
            xcode: .default,
            shell: .default,
            publishCommand: "bash \"$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT\" --version \"$SHIPHOOK_VERSION\" --artifact \"$SHIPHOOK_ARTIFACT_PATH\" --app-name \"YourApp\" --repo-owner \"$SHIPHOOK_GITHUB_OWNER\" --repo-name \"$SHIPHOOK_GITHUB_REPO\" --docs-dir \"$SHIPHOOK_LOCAL_CHECKOUT_PATH/docs\" --releases-dir \"$SHIPHOOK_LOCAL_CHECKOUT_PATH/release-artifacts\" --working-dir \"$SHIPHOOK_LOCAL_CHECKOUT_PATH\"",
            releaseNotesPath: nil,
            githubTokenEnvVar: nil,
            environment: [:],
            versionStrategy: .shortSHATimestamp,
            sparkle: .default,
            signing: .default
        )
    }

    var isPlaceholderExample: Bool {
        id == "example-app"
            && owner == "your-org"
            && repo == "your-app-repo"
    }
}

struct SparkleConfiguration: Codable, Hashable {
    var appcastURL: String?
    var autoIncrementBuild: Bool

    static let `default` = SparkleConfiguration(
        appcastURL: nil,
        autoIncrementBuild: true
    )
}

struct SigningConfiguration: Codable, Hashable {
    var developmentTeam: String?
    var codeSignIdentity: String?
    var codeSignStyle: CodeSignStyle
    var notarizationProfile: String?

    enum CodeSignStyle: String, Codable {
        case automatic
        case manual
    }

    static let `default` = SigningConfiguration(
        developmentTeam: nil,
        codeSignIdentity: nil,
        codeSignStyle: .automatic,
        notarizationProfile: nil
    )
}

struct XcodeBuildConfiguration: Codable, Hashable {
    var projectPath: String?
    var workspacePath: String?
    var scheme: String
    var appName: String
    var configuration: String
    var archivePath: String
    var artifactPath: String

    enum CodingKeys: String, CodingKey {
        case projectPath
        case workspacePath
        case scheme
        case appName
        case configuration
        case archivePath
        case artifactPath
        case exportPath
    }

    static let `default` = XcodeBuildConfiguration(
        projectPath: "",
        workspacePath: nil,
        scheme: "",
        appName: "",
        configuration: "Release",
        archivePath: "",
        artifactPath: ""
    )

    init(
        projectPath: String?,
        workspacePath: String?,
        scheme: String,
        appName: String,
        configuration: String,
        archivePath: String,
        artifactPath: String
    ) {
        self.projectPath = projectPath
        self.workspacePath = workspacePath
        self.scheme = scheme
        self.appName = appName
        self.configuration = configuration
        self.archivePath = archivePath
        self.artifactPath = artifactPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme) ?? ""
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? scheme
        configuration = try container.decodeIfPresent(String.self, forKey: .configuration) ?? "Release"
        archivePath = try container.decodeIfPresent(String.self, forKey: .archivePath) ?? ""

        if let artifact = try container.decodeIfPresent(String.self, forKey: .artifactPath), !artifact.isEmpty {
            artifactPath = artifact
        } else if let exportPath = try container.decodeIfPresent(String.self, forKey: .exportPath), !exportPath.isEmpty {
            artifactPath = exportPath
        } else {
            artifactPath = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(projectPath, forKey: .projectPath)
        try container.encodeIfPresent(workspacePath, forKey: .workspacePath)
        try container.encode(scheme, forKey: .scheme)
        try container.encode(appName, forKey: .appName)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(archivePath, forKey: .archivePath)
        try container.encode(artifactPath, forKey: .artifactPath)
    }
}

extension XcodeBuildConfiguration {
    var sanitizedWorkspacePath: String? {
        guard let workspacePath, !workspacePath.isEmpty else {
            return nil
        }

        // Ignore the implicit workspace nested inside a plain .xcodeproj.
        if workspacePath.contains(".xcodeproj/project.xcworkspace") {
            return nil
        }

        return workspacePath
    }
}

struct ShellBuildConfiguration: Codable, Hashable {
    var command: String
    var artifactPath: String

    static let `default` = ShellBuildConfiguration(
        command: "",
        artifactPath: ""
    )
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

enum RepositoryBuildPhase: String {
    case idle
    case queued
    case syncing
    case planningRelease
    case archiving
    case notarizing
    case publishing
}

struct RepositoryRuntimeState: Identifiable {
    var id: String
    var lastSeenSHA: String?
    var lastBuiltSHA: String?
    var lastCheckDate: Date?
    var lastSuccessDate: Date?
    var buildStartedAt: Date?
    var activity: RepositoryActivity
    var buildPhase: RepositoryBuildPhase
    var summary: String
    var lastLog: String
    var lastLogPath: String?
    var lastError: String?

    static func initial(id: String) -> RepositoryRuntimeState {
        RepositoryRuntimeState(
            id: id,
            lastSeenSHA: nil,
            lastBuiltSHA: nil,
            lastCheckDate: nil,
            lastSuccessDate: nil,
            buildStartedAt: nil,
            activity: .idle,
            buildPhase: .idle,
            summary: "Waiting for first poll",
            lastLog: "",
            lastLogPath: nil,
            lastError: nil
        )
    }
}
