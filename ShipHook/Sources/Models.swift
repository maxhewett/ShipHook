import Foundation

enum AppBuildChannel: String {
    case stable
    case beta

    static var current: AppBuildChannel {
        from(bundle: .main)
    }

    static func from(bundle: Bundle) -> AppBuildChannel {
        if let explicit = bundle.object(forInfoDictionaryKey: "ShipHookIsBetaBuild") as? Bool,
           explicit {
            return .beta
        }

        if let explicit = normalizedString(bundle.object(forInfoDictionaryKey: "ShipHookUpdateChannel")),
           explicit == "beta" {
            return .beta
        }

        if let explicit = normalizedString(bundle.object(forInfoDictionaryKey: "ShipHookReleaseChannel")),
           explicit == "beta" {
            return .beta
        }

        if let feedURL = normalizedString(bundle.object(forInfoDictionaryKey: "SUFeedURL")),
           feedURL.contains("/beta/") {
            return .beta
        }

        if let shortVersion = normalizedString(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")),
           containsBetaMarker(shortVersion) {
            return .beta
        }

        if let buildVersion = normalizedString(bundle.object(forInfoDictionaryKey: "CFBundleVersion")),
           containsBetaMarker(buildVersion) {
            return .beta
        }

        return .stable
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func containsBetaMarker(_ value: String) -> Bool {
        if value.contains("beta") || value.hasPrefix("b") {
            return true
        }

        if value.hasPrefix("pre") || value.hasPrefix("rc") {
            return true
        }

        return false
    }
}

struct AppConfiguration: Codable, Hashable {
    var pollIntervalSeconds: TimeInterval
    var githubToken: String?
    var githubTokenEnvVar: String?
    var generatedDataRetentionCount: Int
    var autoPauseFailureCount: Int
    var webDashboardEnabled: Bool
    var webDashboardPort: Int
    var repositories: [RepositoryConfiguration]

    static let `default` = AppConfiguration(
        pollIntervalSeconds: 300,
        githubToken: nil,
        githubTokenEnvVar: "GITHUB_TOKEN",
        generatedDataRetentionCount: 3,
        autoPauseFailureCount: 3,
        webDashboardEnabled: false,
        webDashboardPort: 8787,
        repositories: []
    )

    var containsOnlyPlaceholderRepository: Bool {
        repositories.count == 1 && repositories[0].isPlaceholderExample
    }

    enum CodingKeys: String, CodingKey {
        case pollIntervalSeconds
        case githubToken
        case githubTokenEnvVar
        case generatedDataRetentionCount
        case autoPauseFailureCount
        case webDashboardEnabled
        case webDashboardPort
        case repositories
    }

    init(
        pollIntervalSeconds: TimeInterval,
        githubToken: String?,
        githubTokenEnvVar: String?,
        generatedDataRetentionCount: Int,
        autoPauseFailureCount: Int,
        webDashboardEnabled: Bool,
        webDashboardPort: Int,
        repositories: [RepositoryConfiguration]
    ) {
        self.pollIntervalSeconds = pollIntervalSeconds
        self.githubToken = githubToken
        self.githubTokenEnvVar = githubTokenEnvVar
        self.generatedDataRetentionCount = max(1, generatedDataRetentionCount)
        self.autoPauseFailureCount = max(1, autoPauseFailureCount)
        self.webDashboardEnabled = webDashboardEnabled
        self.webDashboardPort = webDashboardPort
        self.repositories = repositories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pollIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .pollIntervalSeconds) ?? 300
        githubToken = try container.decodeIfPresent(String.self, forKey: .githubToken)
        githubTokenEnvVar = try container.decodeIfPresent(String.self, forKey: .githubTokenEnvVar) ?? "GITHUB_TOKEN"
        generatedDataRetentionCount = max(1, try container.decodeIfPresent(Int.self, forKey: .generatedDataRetentionCount) ?? 3)
        autoPauseFailureCount = max(1, try container.decodeIfPresent(Int.self, forKey: .autoPauseFailureCount) ?? 3)
        webDashboardEnabled = try container.decodeIfPresent(Bool.self, forKey: .webDashboardEnabled) ?? false
        webDashboardPort = try container.decodeIfPresent(Int.self, forKey: .webDashboardPort) ?? 8787
        repositories = try container.decodeIfPresent([RepositoryConfiguration].self, forKey: .repositories) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pollIntervalSeconds, forKey: .pollIntervalSeconds)
        try container.encodeIfPresent(githubToken, forKey: .githubToken)
        try container.encodeIfPresent(githubTokenEnvVar, forKey: .githubTokenEnvVar)
        try container.encode(max(1, generatedDataRetentionCount), forKey: .generatedDataRetentionCount)
        try container.encode(max(1, autoPauseFailureCount), forKey: .autoPauseFailureCount)
        try container.encode(webDashboardEnabled, forKey: .webDashboardEnabled)
        try container.encode(webDashboardPort, forKey: .webDashboardPort)
        try container.encode(repositories, forKey: .repositories)
    }
}

struct RepositoryConfiguration: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var isEnabled: Bool
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
    var notifications: NotificationConfiguration?
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
        case isEnabled
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
        case notifications
        case signing
    }

    init(
        id: String,
        name: String,
        isEnabled: Bool,
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
        notifications: NotificationConfiguration?,
        signing: SigningConfiguration?
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
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
        self.notifications = notifications
        self.signing = signing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
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
        notifications = try container.decodeIfPresent(NotificationConfiguration.self, forKey: .notifications)
        signing = try container.decodeIfPresent(SigningConfiguration.self, forKey: .signing)
    }

    static func blank() -> RepositoryConfiguration {
        RepositoryConfiguration(
            id: "repo-\(UUID().uuidString.prefix(8).lowercased())",
            name: "New Repository",
            isEnabled: true,
            owner: "",
            repo: "",
            branch: "main",
            localCheckoutPath: "",
            workingDirectory: nil,
            buildOnFirstSeen: false,
            buildMode: .xcodeArchive,
            xcode: .default,
            shell: .default,
            publishCommand: "bash \"$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT\" --version \"$SHIPHOOK_VERSION\" --artifact \"$SHIPHOOK_ARTIFACT_PATH\" --app-name \"YourApp\" --repo-owner \"$SHIPHOOK_GITHUB_OWNER\" --repo-name \"$SHIPHOOK_GITHUB_REPO\" --channel \"$SHIPHOOK_RELEASE_CHANNEL\" --docs-dir \"$SHIPHOOK_LOCAL_CHECKOUT_PATH/docs\" --releases-dir \"$SHIPHOOK_LOCAL_CHECKOUT_PATH/release-artifacts\" --working-dir \"$SHIPHOOK_LOCAL_CHECKOUT_PATH\"",
            releaseNotesPath: nil,
            githubTokenEnvVar: nil,
            environment: [:],
            versionStrategy: .shortSHATimestamp,
            sparkle: .default,
            notifications: .default,
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
    var skipIfVersionIsNotNewer: Bool
    var betaIconPath: String?

    static let `default` = SparkleConfiguration(
        appcastURL: nil,
        autoIncrementBuild: false,
        skipIfVersionIsNotNewer: true,
        betaIconPath: nil
    )

    enum CodingKeys: String, CodingKey {
        case appcastURL
        case autoIncrementBuild
        case skipIfVersionIsNotNewer
        case betaIconPath
    }

    init(
        appcastURL: String?,
        autoIncrementBuild: Bool,
        skipIfVersionIsNotNewer: Bool,
        betaIconPath: String?
    ) {
        self.appcastURL = appcastURL
        self.autoIncrementBuild = autoIncrementBuild
        self.skipIfVersionIsNotNewer = skipIfVersionIsNotNewer
        self.betaIconPath = betaIconPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appcastURL = try container.decodeIfPresent(String.self, forKey: .appcastURL)
        autoIncrementBuild = try container.decodeIfPresent(Bool.self, forKey: .autoIncrementBuild) ?? true
        skipIfVersionIsNotNewer = try container.decodeIfPresent(Bool.self, forKey: .skipIfVersionIsNotNewer) ?? true
        betaIconPath = try container.decodeIfPresent(String.self, forKey: .betaIconPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(appcastURL, forKey: .appcastURL)
        try container.encode(autoIncrementBuild, forKey: .autoIncrementBuild)
        try container.encode(skipIfVersionIsNotNewer, forKey: .skipIfVersionIsNotNewer)
        try container.encodeIfPresent(betaIconPath, forKey: .betaIconPath)
    }
}

struct NotificationConfiguration: Codable, Hashable {
    var discordWebhookURL: String?
    var postOnSuccess: Bool
    var postOnFailure: Bool

    static let `default` = NotificationConfiguration(
        discordWebhookURL: nil,
        postOnSuccess: false,
        postOnFailure: false
    )

    enum CodingKeys: String, CodingKey {
        case discordWebhookURL
        case postOnSuccess
        case postOnFailure
    }

    init(discordWebhookURL: String?, postOnSuccess: Bool, postOnFailure: Bool) {
        self.discordWebhookURL = discordWebhookURL
        self.postOnSuccess = postOnSuccess
        self.postOnFailure = postOnFailure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        discordWebhookURL = try container.decodeIfPresent(String.self, forKey: .discordWebhookURL)
        postOnSuccess = try container.decodeIfPresent(Bool.self, forKey: .postOnSuccess) ?? false
        postOnFailure = try container.decodeIfPresent(Bool.self, forKey: .postOnFailure) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(discordWebhookURL, forKey: .discordWebhookURL)
        try container.encode(postOnSuccess, forKey: .postOnSuccess)
        try container.encode(postOnFailure, forKey: .postOnFailure)
    }
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
    var authorLogin: String?
    var authorAvatarURL: URL?
    var authorProfileURL: URL?
}

enum ReleaseChannel: String, Codable {
    case stable
    case beta
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
    var buildDetail: String?
    var summary: String
    var lastLog: String
    var lastLogPath: String?
    var lastError: String?
    var releaseChannel: ReleaseChannel?
    var lastCommitAuthorLogin: String?
    var lastCommitAuthorAvatarURL: URL?
    var lastCommitAuthorProfileURL: URL?

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
            buildDetail: nil,
            summary: "Waiting for first poll",
            lastLog: "",
            lastLogPath: nil,
            lastError: nil,
            releaseChannel: nil,
            lastCommitAuthorLogin: nil,
            lastCommitAuthorAvatarURL: nil,
            lastCommitAuthorProfileURL: nil
        )
    }
}

struct BuildRecord: Codable, Hashable, Identifiable {
    var id: String
    var repositoryID: String
    var repositoryName: String
    var version: String
    var sha: String
    var builtAt: Date
    var releaseChannel: ReleaseChannel?
    var authorLogin: String?
    var authorAvatarURL: URL?
    var authorProfileURL: URL?
    var summary: String?
    var logPath: String?
}
