import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var configuration: AppConfiguration = .default {
        didSet {
            refreshDirtyState()
            refreshNotarizationProfiles()
            if oldValue.pollIntervalSeconds != configuration.pollIntervalSeconds {
                startPollingLoop()
            }
            if oldValue.webDashboardEnabled != configuration.webDashboardEnabled
                || oldValue.webDashboardPort != configuration.webDashboardPort {
                applyWebDashboardConfiguration()
            }
        }
    }
    @Published private(set) var repoStates: [String: RepositoryRuntimeState] = [:]
    @Published private(set) var configPath: String = ""
    @Published private(set) var lastGlobalError: String?
    @Published private(set) var availableSigningIdentities: [SigningIdentity] = []
    @Published private(set) var availableNotarizationProfiles: [String] = []
    @Published private(set) var lastSigningIdentityError: String?
    @Published private(set) var signingDiagnostics: SigningDiagnostics?
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var buildHistory: [BuildRecord] = []
    @Published private(set) var buildCommitAuthors: [String: String] = [:]
    @Published private(set) var buildCommitAuthorAvatarURLs: [String: URL] = [:]
    @Published private(set) var buildCommitAuthorProfileURLs: [String: URL] = [:]
    @Published private(set) var latestPublishedVersions: [String: AppcastVersion] = [:]
    @Published private(set) var releasesByRepository: [String: [GitHubReleaseSummary]] = [:]
    @Published private(set) var releaseExplorerErrors: [String: String] = [:]
    @Published private(set) var releaseExplorerLoadingRepositoryIDs: Set<String> = []
    @Published private(set) var releaseExplorerLastRefreshedAt: [String: Date] = [:]
    @Published private(set) var launchesAtLogin = false
    @Published private(set) var launchAtLoginStatusMessage: String?
    @Published private(set) var webDashboardStatusMessage = "Local web dashboard is turned off."
    @Published private(set) var webDashboardURLString: String?

    private var configStore = ConfigStore()
    private let buildHistoryStore = BuildHistoryStore()
    private let githubAPI = GitHubAPI()
    private let pipelineRunner = PipelineRunner()
    private let projectInspector = ProjectInspector()
    private let releasePlanner = ReleasePlanner()
    private let signingInspector = SigningInspector()
    private let commandRunner = ShellCommandRunner()
    private var buildHistoryByRepository: [String: [BuildRecord]] = [:]
    private var latestBuildByRepository: [String: BuildRecord] = [:]
    private var webIconDataByRepositoryID: [String: String] = [:]
    private var buildCommitAuthorLookupInFlight: Set<String> = []
    private var buildCommitAuthorLookupInFlightKeys: Set<String> = []
    private var pollingTask: Task<Void, Never>?
    private var inFlightBuilds: Set<String> = []
    private var queuedBuilds: [String: (repository: RepositoryConfiguration, snapshot: GitHubBranchSnapshot)] = [:]
    private var queuedBuildOrder: [String] = []
    private var activeBuildRepositoryID: String?
    private var buildVersionsInFlight: [String: AppVersion] = [:]
    private var logBuffers: [String: String] = [:]
    private var logFlushTasks: [String: Task<Void, Never>] = [:]
    private var consecutiveBuildFailures: [String: Int] = [:]
    private let ignoredCommitMarkers = ["[shiphook skip]", "[skip shiphook]"]
    private let notarizationProfilesDefaultsKey = "ShipHookKnownNotarizationProfiles"
    private var lastSavedConfiguration: AppConfiguration = .default
    private lazy var webDashboardServer = WebDashboardServer { [weak self] in
        self?.makeWebDashboardSnapshot() ?? WebDashboardSnapshot(generatedAt: Date(), repositories: [])
    }

    init() {
        loadConfiguration()
        loadBuildHistory()
        refreshSigningIdentities()
        refreshNotarizationProfiles()
        refreshLaunchAtLoginStatus()
        refreshPublishedVersions()
        applyWebDashboardConfiguration()
        startPollingLoop()
    }

    deinit {
        pollingTask?.cancel()
    }

    func loadConfiguration() {
        do {
            configuration = try configStore.loadConfiguration()
            normalizeConfiguration()
            configPath = configStore.configURL.path
            lastSavedConfiguration = configuration
            synchronizeRuntimeState()
            refreshDirtyState()
            refreshNotarizationProfiles()
            refreshPublishedVersions()
            lastGlobalError = nil
        } catch {
            lastGlobalError = error.localizedDescription
        }
    }

    func saveConfiguration() {
        do {
            normalizeConfiguration()
            configuration.repositories = configuration.repositories.map { repository in
                var repository = repository
                if repository.buildMode == .xcodeArchive && repository.xcode == nil {
                    repository.xcode = .default
                }
                if repository.buildMode == .shell && repository.shell == nil {
                    repository.shell = .default
                }
                if repository.sparkle == nil {
                    repository.sparkle = .default
                }
                if repository.notifications == nil {
                    repository.notifications = .default
                }
                if repository.signing == nil {
                    repository.signing = .default
                }
                return repository
            }
            try configStore.saveConfiguration(configuration)
            lastSavedConfiguration = configuration
            synchronizeRuntimeState()
            refreshDirtyState()
            refreshNotarizationProfiles()
            refreshPublishedVersions()
            lastGlobalError = nil
        } catch {
            lastGlobalError = error.localizedDescription
        }
    }

    func addRepository() -> String {
        let repository = RepositoryConfiguration.blank()
        configuration.repositories.append(repository)
        repoStates[repository.id] = .initial(id: repository.id)
        return repository.id
    }

    func removeRepositories(atOffsets offsets: IndexSet) {
        let idsToRemove = offsets.map { configuration.repositories[$0].id }
        configuration.repositories.remove(atOffsets: offsets)
        idsToRemove.forEach { repositoryID in
            repoStates.removeValue(forKey: repositoryID)
            inFlightBuilds.remove(repositoryID)
            queuedBuilds.removeValue(forKey: repositoryID)
            queuedBuildOrder.removeAll { queuedID in queuedID == repositoryID }
            buildHistoryByRepository.removeValue(forKey: repositoryID)
            latestBuildByRepository.removeValue(forKey: repositoryID)
            latestPublishedVersions.removeValue(forKey: repositoryID)
            releasesByRepository.removeValue(forKey: repositoryID)
            webIconDataByRepositoryID.removeValue(forKey: repositoryID)
            releaseExplorerErrors.removeValue(forKey: repositoryID)
            releaseExplorerLoadingRepositoryIDs.remove(repositoryID)
            releaseExplorerLastRefreshedAt.removeValue(forKey: repositoryID)
            buildCommitAuthors = buildCommitAuthors.filter { key, _ in
                !key.hasPrefix("\(repositoryID)|")
            }
            buildCommitAuthorAvatarURLs = buildCommitAuthorAvatarURLs.filter { key, _ in
                !key.hasPrefix("\(repositoryID)|")
            }
            buildCommitAuthorProfileURLs = buildCommitAuthorProfileURLs.filter { key, _ in
                !key.hasPrefix("\(repositoryID)|")
            }
            buildCommitAuthorLookupInFlight.remove(repositoryID)
            buildCommitAuthorLookupInFlightKeys = buildCommitAuthorLookupInFlightKeys.filter { key in
                !key.hasPrefix("\(repositoryID)|")
            }
            logBuffers.removeValue(forKey: repositoryID)
            logFlushTasks[repositoryID]?.cancel()
            logFlushTasks.removeValue(forKey: repositoryID)
        }
    }

    func makeRepositoryFromInspection(
        localCheckoutPath: String,
        fallbackOwner: String,
        fallbackRepo: String,
        fallbackBranch: String,
        selectedScheme: String?
    ) throws -> RepositoryConfiguration {
        let inspection = try inspectCheckout(localCheckoutPath: localCheckoutPath)
        let scheme = selectedScheme ?? inspection.suggestedScheme ?? ""
        let owner = !(inspection.owner ?? "").isEmpty ? inspection.owner! : fallbackOwner
        let checkoutFolderName = URL(fileURLWithPath: (localCheckoutPath as NSString).expandingTildeInPath).lastPathComponent
        let repo = !(inspection.repo ?? "").isEmpty ? inspection.repo! : (fallbackRepo.isEmpty ? checkoutFolderName : fallbackRepo)
        let branch = !(inspection.branch ?? "").isEmpty ? inspection.branch! : fallbackBranch
        let safeName = (scheme.isEmpty ? repo : scheme).replacingOccurrences(of: " ", with: "-")
        let archivePath = defaultArchivePath(appName: safeName)
        let appName = scheme.isEmpty ? repo : scheme
        let artifactPath = "\(archivePath)/Products/Applications/\(appName).app"

        return RepositoryConfiguration(
            id: "repo-\(UUID().uuidString.prefix(8).lowercased())",
            name: appName.isEmpty ? repo : appName,
            isEnabled: true,
            owner: owner,
            repo: repo,
            branch: branch.isEmpty ? "main" : branch,
            localCheckoutPath: localCheckoutPath,
            workingDirectory: localCheckoutPath,
            buildOnFirstSeen: false,
            buildMode: .xcodeArchive,
            xcode: XcodeBuildConfiguration(
                projectPath: inspection.projectPath,
                workspacePath: inspection.workspacePath,
                scheme: scheme,
                appName: appName,
                configuration: "Release",
                archivePath: archivePath,
                artifactPath: artifactPath
            ),
            shell: .default,
            publishCommand: """
            bash "$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT" --version "$SHIPHOOK_VERSION" --artifact "$SHIPHOOK_ARTIFACT_PATH" --app-name "\(appName)" --repo-owner "$SHIPHOOK_GITHUB_OWNER" --repo-name "$SHIPHOOK_GITHUB_REPO" --channel "$SHIPHOOK_RELEASE_CHANNEL" --release-notes "$SHIPHOOK_RELEASE_NOTES_PATH" --docs-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/docs" --releases-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/release-artifacts" --working-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH"
            """,
            releaseNotesPath: inspection.releaseNotesPath,
            githubTokenEnvVar: nil,
            environment: [:],
            versionStrategy: .shortSHATimestamp,
            sparkle: SparkleConfiguration(
                appcastURL: defaultAppcastURL(owner: owner, repo: repo),
                autoIncrementBuild: false,
                skipIfVersionIsNotNewer: true,
                betaIconPath: nil
            ),
            notifications: .default,
            signing: .default
        )
    }

    func addRepository(_ repository: RepositoryConfiguration) -> String {
        configuration.repositories.append(repository)
        repoStates[repository.id] = .initial(id: repository.id)
        return repository.id
    }

    func inspectCheckout(localCheckoutPath: String) throws -> ProjectInspectionResult {
        try projectInspector.inspect(localCheckoutPath: localCheckoutPath)
    }

    func inspectReleaseState(for repository: RepositoryConfiguration) throws -> ReleaseInspection? {
        try releasePlanner.inspectReleaseState(for: repository)
    }

    func defaultAppcastURL(owner: String, repo: String) -> String? {
        guard !owner.isEmpty, !repo.isEmpty else {
            return nil
        }
        return "https://\(owner).github.io/\(repo)/appcast.xml"
    }

    func defaultArchivePath(appName: String, now: Date = Date()) -> String {
        let archivesRoot = ("~/Library/Developer/Xcode/Archives" as NSString).expandingTildeInPath

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH.mm.ss"

        let safeAppName = appName.isEmpty ? "App" : appName
        return "\(archivesRoot)/\(dayFormatter.string(from: now))/\(safeAppName) \(timeFormatter.string(from: now)).xcarchive"
    }

    func refreshSigningIdentities() {
        do {
            let inspection = try signingInspector.inspectAvailableIdentities()
            availableSigningIdentities = inspection.identities
            lastSigningIdentityError = nil
            signingDiagnostics = try signingInspector.diagnostics()
        } catch {
            availableSigningIdentities = []
            lastSigningIdentityError = error.localizedDescription
            signingDiagnostics = nil
        }
    }

    func storeNotarizationProfile(
        profileName: String,
        appleID: String,
        teamID: String,
        appSpecificPassword: String
    ) throws {
        let trimmedProfileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAppleID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTeamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = appSpecificPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedProfileName.isEmpty,
              !trimmedAppleID.isEmpty,
              !trimmedTeamID.isEmpty,
              !trimmedPassword.isEmpty else {
            throw NSError(
                domain: "ShipHook",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Profile name, Apple ID, Team ID, and app-specific password are all required."]
            )
        }

        _ = try commandRunner.run(
            """
            xcrun notarytool store-credentials "$SHIPHOOK_NOTARY_PROFILE" \
              --apple-id "$SHIPHOOK_NOTARY_APPLE_ID" \
              --team-id "$SHIPHOOK_NOTARY_TEAM_ID" \
              --password "$SHIPHOOK_NOTARY_PASSWORD"
            """,
            currentDirectory: NSHomeDirectory(),
            environment: [
                "SHIPHOOK_NOTARY_PROFILE": trimmedProfileName,
                "SHIPHOOK_NOTARY_APPLE_ID": trimmedAppleID,
                "SHIPHOOK_NOTARY_TEAM_ID": trimmedTeamID,
                "SHIPHOOK_NOTARY_PASSWORD": trimmedPassword,
            ]
        )
        registerNotarizationProfile(trimmedProfileName)
    }

    func triggerManualPoll() {
        Task {
            await checkRepositories(force: true, repositoryID: nil)
        }
    }

    func triggerManualPoll(for repositoryID: String) {
        Task {
            await checkRepositories(force: true, repositoryID: repositoryID)
        }
    }

    func triggerManualPollAll() {
        Task {
            await checkRepositories(force: true, repositoryID: nil)
        }
    }

    func refreshReleaseExplorer(for repositoryID: String) {
        refreshReleaseExplorer(for: repositoryID, force: true)
    }

    func refreshReleaseExplorer(for repositoryID: String, force: Bool) {
        guard let repository = configuration.repositories.first(where: { $0.id == repositoryID }) else {
            return
        }
        if releaseExplorerLoadingRepositoryIDs.contains(repositoryID) {
            return
        }
        if !force,
           let lastRefresh = releaseExplorerLastRefreshedAt[repositoryID],
           Date().timeIntervalSince(lastRefresh) < 120,
           releasesByRepository[repositoryID] != nil {
            return
        }

        let token = githubToken(for: repository)
        let githubAPI = self.githubAPI
        releaseExplorerLoadingRepositoryIDs.insert(repositoryID)
        releaseExplorerErrors.removeValue(forKey: repositoryID)

        Task.detached(priority: .utility) {
            do {
                let releases = try await githubAPI.listReleases(
                    owner: repository.owner,
                    repo: repository.repo,
                    token: token,
                    perPage: 30
                )
                await MainActor.run {
                    self.releasesByRepository[repositoryID] = releases
                    self.releaseExplorerLastRefreshedAt[repositoryID] = Date()
                    self.releaseExplorerLoadingRepositoryIDs.remove(repositoryID)
                }
            } catch {
                await MainActor.run {
                    self.releaseExplorerErrors[repositoryID] = error.localizedDescription
                    self.releaseExplorerLoadingRepositoryIDs.remove(repositoryID)
                }
            }
        }
    }

    func rollbackRelease(repositoryID: String, release: GitHubReleaseSummary) {
        guard let repository = configuration.repositories.first(where: { $0.id == repositoryID }) else {
            return
        }

        let token = githubToken(for: repository)
        let githubAPI = self.githubAPI
        releaseExplorerLoadingRepositoryIDs.insert(repositoryID)
        releaseExplorerErrors.removeValue(forKey: repositoryID)

        Task.detached(priority: .userInitiated) {
            do {
                let summary = try await Self.performReleaseRollback(
                    repository: repository,
                    release: release,
                    token: token,
                    githubAPI: githubAPI
                )

                let releases = try await githubAPI.listReleases(
                    owner: repository.owner,
                    repo: repository.repo,
                    token: token,
                    perPage: 30
                )

                await MainActor.run {
                    self.releasesByRepository[repositoryID] = releases
                    self.releaseExplorerLastRefreshedAt[repositoryID] = Date()
                    self.releaseExplorerLoadingRepositoryIDs.remove(repositoryID)
                    self.releaseExplorerErrors.removeValue(forKey: repositoryID)
                    self.updateState(for: repositoryID) {
                        $0.summary = summary
                    }
                    self.refreshPublishedVersions()
                }
            } catch {
                await MainActor.run {
                    self.releaseExplorerErrors[repositoryID] = error.localizedDescription
                    self.releaseExplorerLoadingRepositoryIDs.remove(repositoryID)
                }
            }
        }
    }

    func openConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
    }

    func openWebDashboard() {
        guard let webDashboardURLString,
              let url = URL(string: webDashboardURLString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            launchesAtLogin = status == .enabled
            switch status {
            case .enabled:
                launchAtLoginStatusMessage = "ShipHook will open automatically when you log in."
            case .requiresApproval:
                launchAtLoginStatusMessage = "Login launch is waiting for approval in System Settings."
            case .notFound:
                launchAtLoginStatusMessage = "Install ShipHook in Applications before enabling launch at login."
            case .notRegistered:
                launchAtLoginStatusMessage = "Launch at login is turned off."
            @unknown default:
                launchAtLoginStatusMessage = nil
            }
        } else {
            launchesAtLogin = false
            launchAtLoginStatusMessage = "Launch at login requires a newer version of macOS."
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw NSError(
                domain: "ShipHook",
                code: 501,
                userInfo: [NSLocalizedDescriptionKey: "Launch at login requires a newer version of macOS."]
            )
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        refreshLaunchAtLoginStatus()
    }

    func publishedVersion(for repository: RepositoryConfiguration) -> String? {
        guard let published = latestPublishedVersions[repository.id] else {
            return nil
        }

        if let marketingVersion = published.marketingVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !marketingVersion.isEmpty {
            return marketingVersion
        }

        let buildVersion = published.buildVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return buildVersion.isEmpty ? nil : buildVersion
    }

    func history(for repositoryID: String) -> [BuildRecord] {
        buildHistoryByRepository[repositoryID] ?? []
    }

    func latestBuildRecord(for repositoryID: String) -> BuildRecord? {
        latestBuildByRepository[repositoryID]
    }

    func buildCommitAuthor(for repositoryID: String, sha: String) -> String? {
        buildCommitAuthors["\(repositoryID)|\(sha.lowercased())"]
    }

    func buildCommitAuthorAvatarURL(for repositoryID: String, sha: String) -> URL? {
        buildCommitAuthorAvatarURLs["\(repositoryID)|\(sha.lowercased())"]
    }

    func buildCommitAuthorProfileURL(for repositoryID: String, sha: String) -> URL? {
        buildCommitAuthorProfileURLs["\(repositoryID)|\(sha.lowercased())"]
    }

    func ensureBuildCommitAuthor(for repositoryID: String, sha: String) {
        let key = "\(repositoryID)|\(sha.lowercased())"
        if buildCommitAuthors[key] != nil || buildCommitAuthorLookupInFlightKeys.contains(key) {
            return
        }
        guard let repository = configuration.repositories.first(where: { $0.id == repositoryID }) else {
            return
        }

        buildCommitAuthorLookupInFlightKeys.insert(key)
        let checkoutPath = (repository.localCheckoutPath as NSString).expandingTildeInPath
        let token = githubToken(for: repository)
        let githubAPI = self.githubAPI

        Task.detached(priority: .utility) {
            var resolvedDisplayName: String?
            var resolvedAvatarURL: URL?
            var resolvedProfileURL: URL?

            if let remoteAuthor = try? await githubAPI.commitAuthor(
                owner: repository.owner,
                repo: repository.repo,
                sha: sha,
                token: token
            ) {
                resolvedDisplayName = remoteAuthor.displayName
                resolvedAvatarURL = remoteAuthor.avatarURL
                resolvedProfileURL = remoteAuthor.profileURL
            } else if let author = Self.resolveGitCommitAuthor(checkoutPath: checkoutPath, sha: sha),
                      !author.isEmpty {
                resolvedDisplayName = author
            }
            let finalDisplayName = resolvedDisplayName
            let finalAvatarURL = resolvedAvatarURL
            let finalProfileURL = resolvedProfileURL

            await MainActor.run {
                self.buildCommitAuthorLookupInFlightKeys.remove(key)
                if let finalDisplayName, !finalDisplayName.isEmpty {
                    self.buildCommitAuthors[key] = finalDisplayName
                }
                if let finalAvatarURL {
                    self.buildCommitAuthorAvatarURLs[key] = finalAvatarURL
                }
                if let finalProfileURL {
                    self.buildCommitAuthorProfileURLs[key] = finalProfileURL
                }
            }
        }
    }

    func preloadBuildCommitAuthors(for repositoryID: String) {
        guard !buildCommitAuthorLookupInFlight.contains(repositoryID) else {
            return
        }
        guard let repository = configuration.repositories.first(where: { $0.id == repositoryID }) else {
            return
        }
        let records = Array((buildHistoryByRepository[repositoryID] ?? []).prefix(36))
        guard !records.isEmpty else {
            return
        }

        let checkoutPath = (repository.localCheckoutPath as NSString).expandingTildeInPath
        let token = githubToken(for: repository)
        let githubAPI = self.githubAPI
        let unresolved = records.filter { record in
            let key = "\(repositoryID)|\(record.sha.lowercased())"
            if buildCommitAuthors[key] != nil {
                return false
            }
            return true
        }

        guard !unresolved.isEmpty else {
            return
        }
        buildCommitAuthorLookupInFlight.insert(repositoryID)

        Task.detached(priority: .utility) {
            var resolved: [String: String] = [:]
            var avatars: [String: URL] = [:]
            var profiles: [String: URL] = [:]
            let unresolvedKeys = unresolved.map { "\(repositoryID)|\($0.sha.lowercased())" }

            await MainActor.run {
                for key in unresolvedKeys {
                    self.buildCommitAuthorLookupInFlightKeys.insert(key)
                }
            }

            for record in unresolved {
                let key = "\(repositoryID)|\(record.sha.lowercased())"

                if let login = record.authorLogin, !login.isEmpty {
                    resolved[key] = "@\(login)"
                    if let avatar = record.authorAvatarURL {
                        avatars[key] = avatar
                    }
                    if let profile = record.authorProfileURL {
                        profiles[key] = profile
                    }
                    continue
                }

                if let remoteAuthor = try? await githubAPI.commitAuthor(
                    owner: repository.owner,
                    repo: repository.repo,
                    sha: record.sha,
                    token: token
                ) {
                    resolved[key] = remoteAuthor.displayName
                    if let avatar = remoteAuthor.avatarURL {
                        avatars[key] = avatar
                    }
                    if let profile = remoteAuthor.profileURL {
                        profiles[key] = profile
                    }
                    continue
                }

                if let author = Self.resolveGitCommitAuthor(checkoutPath: checkoutPath, sha: record.sha),
                   !author.isEmpty {
                    resolved[key] = author
                }
            }
            let resolvedAuthors = resolved
            let resolvedAvatars = avatars
            let resolvedProfiles = profiles

            await MainActor.run {
                self.buildCommitAuthorLookupInFlight.remove(repositoryID)
                self.buildCommitAuthors.merge(resolvedAuthors) { current, _ in current }
                self.buildCommitAuthorAvatarURLs.merge(resolvedAvatars) { current, _ in current }
                self.buildCommitAuthorProfileURLs.merge(resolvedProfiles) { current, _ in current }
                for record in unresolved {
                    let key = "\(repositoryID)|\(record.sha.lowercased())"
                    self.buildCommitAuthorLookupInFlightKeys.remove(key)
                }
            }
        }
    }

    func displayedVersion(for repository: RepositoryConfiguration) -> String? {
        if let localVersion = latestBuildRecord(for: repository.id)?.version, !localVersion.isEmpty {
            return localVersion
        }

        guard let published = latestPublishedVersions[repository.id] else {
            return nil
        }

        if let marketingVersion = published.marketingVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !marketingVersion.isEmpty {
            return marketingVersion
        }

        let buildVersion = published.buildVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return buildVersion.isEmpty ? nil : buildVersion
    }

    func resetBuildState(for repositoryID: String) {
        inFlightBuilds.remove(repositoryID)
        queuedBuilds.removeValue(forKey: repositoryID)
        queuedBuildOrder.removeAll { $0 == repositoryID }
        buildVersionsInFlight.removeValue(forKey: repositoryID)
        logBuffers.removeValue(forKey: repositoryID)
        logFlushTasks[repositoryID]?.cancel()
        logFlushTasks.removeValue(forKey: repositoryID)
        consecutiveBuildFailures[repositoryID] = 0
        if activeBuildRepositoryID == repositoryID {
            activeBuildRepositoryID = nil
        }
        updateState(for: repositoryID) {
            $0.activity = .idle
            $0.buildStartedAt = nil
            $0.buildPhase = .idle
            $0.summary = "Build state reset. Ready to check again."
        }
        startNextQueuedBuildIfPossible()
    }

    private func normalizeConfiguration() {
        configuration.generatedDataRetentionCount = max(1, configuration.generatedDataRetentionCount)
        configuration.autoPauseFailureCount = max(1, configuration.autoPauseFailureCount)
        configuration.repositories = configuration.repositories.map { repository in
            var repository = repository
            if var xcode = repository.xcode {
                xcode.workspacePath = xcode.sanitizedWorkspacePath
                repository.xcode = xcode
            }
            repository.publishCommand = normalizedPublishCommand(repository.publishCommand)
            return repository
        }
    }

    private func normalizedPublishCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return command
        }
        guard trimmed.contains("$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT") else {
            return command
        }
        guard !trimmed.contains("--channel \"$SHIPHOOK_RELEASE_CHANNEL\""),
              !trimmed.contains("--channel '$SHIPHOOK_RELEASE_CHANNEL'"),
              !trimmed.contains("--channel=") else {
            return command
        }
        return "\(command) --channel \"$SHIPHOOK_RELEASE_CHANNEL\""
    }

    private func refreshDirtyState() {
        hasUnsavedChanges = configuration != lastSavedConfiguration
    }

    private func applyWebDashboardConfiguration() {
        let status = webDashboardServer.configure(
            enabled: configuration.webDashboardEnabled,
            port: configuration.webDashboardPort
        )
        webDashboardStatusMessage = status.message
        webDashboardURLString = status.urlString
    }

    private func refreshNotarizationProfiles() {
        let storedProfiles = UserDefaults.standard.stringArray(forKey: notarizationProfilesDefaultsKey) ?? []
        let configuredProfiles = configuration.repositories.compactMap { repository in
            repository.signing?.notarizationProfile?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let profiles = Set(
            (storedProfiles + configuredProfiles)
                .filter { !$0.isEmpty }
        )
        availableNotarizationProfiles = profiles.sorted()
    }

    private func registerNotarizationProfile(_ profileName: String) {
        let trimmedProfileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfileName.isEmpty else {
            return
        }
        var profiles = Set(UserDefaults.standard.stringArray(forKey: notarizationProfilesDefaultsKey) ?? [])
        profiles.insert(trimmedProfileName)
        UserDefaults.standard.set(Array(profiles).sorted(), forKey: notarizationProfilesDefaultsKey)
        refreshNotarizationProfiles()
    }

    private func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                let cycleStartedAt = Date()
                await checkRepositories(force: false)
                let interval = max(60, configuration.pollIntervalSeconds)
                let elapsed = Date().timeIntervalSince(cycleStartedAt)
                let remaining = max(0, interval - elapsed)
                try? await Task.sleep(for: .seconds(remaining))
            }
        }
    }

    private func checkRepositories(force: Bool, repositoryID: String? = nil) async {
        for repository in configuration.repositories {
            if let repositoryID, repository.id != repositoryID {
                continue
            }
            await check(repository: repository, force: force)
        }
    }

    private func check(repository: RepositoryConfiguration, force: Bool) async {
        if !repository.isEnabled {
            updateState(for: repository.id) {
                $0.activity = .idle
                $0.buildPhase = .idle
                $0.summary = "Repository is paused"
                $0.lastCheckDate = Date()
            }
            return
        }

            updateState(for: repository.id) {
                $0.activity = .polling
                $0.buildPhase = .idle
                $0.summary = "Checking GitHub branch \(repository.branch)"
                $0.lastCheckDate = Date()
            }

        do {
            let token = githubToken(for: repository)
            let snapshot = try await githubAPI.latestBranchSnapshot(
                owner: repository.owner,
                repo: repository.repo,
                branch: repository.branch,
                token: token
            )

            let currentState = repoStates[repository.id] ?? .initial(id: repository.id)
            updateState(for: repository.id) {
                $0.lastSeenSHA = snapshot.sha
                $0.summary = "Latest GitHub commit \(snapshot.sha.prefix(7))"
                $0.activity = .idle
                $0.lastError = nil
                $0.lastCommitAuthorLogin = snapshot.authorLogin
                $0.lastCommitAuthorAvatarURL = snapshot.authorAvatarURL
                $0.lastCommitAuthorProfileURL = snapshot.authorProfileURL
            }
            let sawNewCommit = currentState.lastSeenSHA != snapshot.sha
            let shouldForceReleaseRefresh = force || sawNewCommit
            maybeRefreshReleaseExplorer(for: repository.id, force: shouldForceReleaseRefresh)

            if shouldIgnore(snapshot: snapshot) {
                updateState(for: repository.id) {
                    $0.activity = .idle
                    $0.buildPhase = .idle
                    $0.summary = "Ignoring ShipHook-managed commit \(snapshot.sha.prefix(7))"
                    $0.lastError = nil
                }
                return
            }

            if currentState.lastSeenSHA == nil && !repository.buildOnFirstSeen && !force {
                updateState(for: repository.id) {
                    $0.summary = "Baseline set to \(snapshot.sha.prefix(7)); waiting for the next push"
                }
                return
            }

            if currentState.lastBuiltSHA == snapshot.sha && !force {
                updateState(for: repository.id) {
                    $0.summary = "No new pushes since \(snapshot.sha.prefix(7))"
                }
                return
            }

            if inFlightBuilds.contains(repository.id) {
                if activeBuildRepositoryID != repository.id {
                    updateState(for: repository.id) {
                        $0.summary = "Build already in progress"
                    }
                }
                return
            }

            if let activeBuildRepositoryID, activeBuildRepositoryID != repository.id {
                queuedBuilds[repository.id] = (repository, snapshot)
                if !queuedBuildOrder.contains(repository.id) {
                    queuedBuildOrder.append(repository.id)
                }
                let activeName = configuration.repositories.first(where: { $0.id == activeBuildRepositoryID })?.name ?? activeBuildRepositoryID
                updateState(for: repository.id) {
                    $0.activity = .building
                    $0.buildPhase = .queued
                    $0.summary = "Queued behind \(activeName)"
                    $0.lastSeenSHA = snapshot.sha
                    $0.lastCommitAuthorLogin = snapshot.authorLogin
                    $0.lastCommitAuthorAvatarURL = snapshot.authorAvatarURL
                    $0.lastCommitAuthorProfileURL = snapshot.authorProfileURL
                }
                return
            }

            inFlightBuilds.insert(repository.id)
            activeBuildRepositoryID = repository.id
            let releaseChannel = releaseChannel(for: snapshot)
            buildVersionsInFlight.removeValue(forKey: repository.id)
            logBuffers[repository.id] = ""
            logFlushTasks[repository.id]?.cancel()
            logFlushTasks.removeValue(forKey: repository.id)
            updateState(for: repository.id) {
                $0.activity = .building
                $0.buildStartedAt = Date()
                $0.buildPhase = .syncing
                $0.summary = "Building commit \(snapshot.sha.prefix(7))"
                $0.lastLogPath = "\((repository.localCheckoutPath as NSString).expandingTildeInPath)/.shiphook/logs/\(repository.id)-latest.log"
                $0.lastLog = ""
                $0.releaseChannel = releaseChannel
                $0.lastCommitAuthorLogin = snapshot.authorLogin
                $0.lastCommitAuthorAvatarURL = snapshot.authorAvatarURL
                $0.lastCommitAuthorProfileURL = snapshot.authorProfileURL
            }

            let runner = pipelineRunner
            Task.detached { [weak self] in
                let result: Result<PipelineOutcome, Error> = Result {
                    try runner.run(repository: repository, snapshot: snapshot, onStageChange: { stage in
                        Task { @MainActor [weak self] in
                            self?.updateBuildStage(stage, for: repository.id, sha: snapshot.sha)
                        }
                    }, onVersionResolved: { version in
                        Task { @MainActor [weak self] in
                            self?.updateResolvedBuildVersion(version, for: repository.id, sha: snapshot.sha)
                        }
                    }, onOutput: { chunk in
                        Task { @MainActor [weak self] in
                            self?.appendLog(chunk, for: repository.id)
                        }
                    })
                }
                await self?.finishBuild(for: repository, snapshot: snapshot, result: result)
            }
        } catch {
            handleFailure(
                for: repository,
                snapshot: nil,
                error: error,
                summary: "GitHub poll failed: \(error.localizedDescription)",
                incrementsFailureStreak: false
            )
        }
    }

    private func finishBuild(
        for repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot,
        result: Result<PipelineOutcome, Error>
    ) {
        inFlightBuilds.remove(repository.id)
        buildVersionsInFlight.removeValue(forKey: repository.id)
        flushLogBuffer(for: repository.id)
        logBuffers.removeValue(forKey: repository.id)
        logFlushTasks[repository.id]?.cancel()
        logFlushTasks.removeValue(forKey: repository.id)
        if activeBuildRepositoryID == repository.id {
            activeBuildRepositoryID = nil
        }

        switch result {
        case let .success(outcome):
            if outcome.skippedPublish {
                updateState(for: repository.id) {
                    $0.activity = .idle
                    $0.lastBuiltSHA = outcome.builtSHA
                    $0.buildStartedAt = nil
                    $0.buildPhase = .idle
                    $0.lastLog = tailLines(from: outcome.log, limit: 120)
                    $0.lastLogPath = outcome.logPath
                    $0.lastError = nil
                    $0.summary = outcome.summary
                    $0.releaseChannel = outcome.releaseChannel
                }
                consecutiveBuildFailures[repository.id] = 0
                startNextQueuedBuildIfPossible()
                return
            }
            let historyRecord = BuildRecord(
                id: UUID().uuidString,
                repositoryID: repository.id,
                repositoryName: repository.name,
                version: outcome.version,
                sha: outcome.builtSHA,
                builtAt: Date(),
                releaseChannel: outcome.releaseChannel,
                authorLogin: snapshot.authorLogin,
                authorAvatarURL: snapshot.authorAvatarURL,
                authorProfileURL: snapshot.authorProfileURL,
                summary: outcome.summary,
                logPath: outcome.logPath
            )
            appendBuildRecord(historyRecord)
            updateState(for: repository.id) {
                $0.activity = .succeeded
                $0.lastBuiltSHA = outcome.builtSHA
                $0.lastSuccessDate = historyRecord.builtAt
                $0.buildStartedAt = nil
                $0.buildPhase = .idle
                $0.lastLog = tailLines(from: outcome.log, limit: 120)
                $0.lastLogPath = outcome.logPath
                $0.lastError = nil
                $0.summary = outcome.summary
                $0.releaseChannel = outcome.releaseChannel
            }
            consecutiveBuildFailures[repository.id] = 0
            refreshReleaseExplorer(for: repository.id, force: true)
        case let .failure(error):
            handleFailure(
                for: repository,
                snapshot: snapshot,
                error: error,
                summary: "Build or publish failed",
                incrementsFailureStreak: true
            )
        }

        pruneGeneratedData(for: repository)
        startNextQueuedBuildIfPossible()
    }

    private func maybeRefreshReleaseExplorer(for repositoryID: String, force: Bool) {
        if force || releasesByRepository[repositoryID] == nil {
            refreshReleaseExplorer(for: repositoryID, force: true)
            return
        }

        if let lastRefresh = releaseExplorerLastRefreshedAt[repositoryID],
           Date().timeIntervalSince(lastRefresh) > 15 * 60 {
            refreshReleaseExplorer(for: repositoryID, force: true)
        }
    }

    private func updateBuildStage(_ stage: PipelineStage, for repositoryID: String, sha: String) {
        updateState(for: repositoryID) {
            $0.activity = .building
            switch stage {
            case let .syncing(message):
                $0.buildPhase = .syncing
                $0.summary = stageSummary(for: .syncing, sha: sha, detail: message, repositoryID: repositoryID)
            case .planningRelease:
                $0.buildPhase = .planningRelease
                $0.summary = stageSummary(for: .planningRelease, sha: sha, detail: nil, repositoryID: repositoryID)
            case .archiving:
                $0.buildPhase = .archiving
                $0.summary = stageSummary(for: .archiving, sha: sha, detail: nil, repositoryID: repositoryID)
            case .notarizing:
                $0.buildPhase = .notarizing
                $0.summary = stageSummary(for: .notarizing, sha: sha, detail: nil, repositoryID: repositoryID)
            case .publishing:
                $0.buildPhase = .publishing
                $0.summary = stageSummary(for: .publishing, sha: sha, detail: nil, repositoryID: repositoryID)
            }
        }
    }

    private func updateResolvedBuildVersion(_ version: AppVersion, for repositoryID: String, sha: String) {
        buildVersionsInFlight[repositoryID] = version
        updateState(for: repositoryID) { state in
            guard state.activity == .building else {
                return
            }
            state.summary = stageSummary(for: state.buildPhase, sha: sha, detail: nil, repositoryID: repositoryID)
        }
    }

    private func stageSummary(for phase: RepositoryBuildPhase, sha: String, detail: String?, repositoryID: String) -> String {
        let shortSHA = String(sha.prefix(7))
        let buildContext = buildContextSuffix(for: repositoryID)
        switch phase {
        case .idle:
            return "Building commit \(shortSHA)\(buildContext)"
        case .queued:
            return "Queued for build \(shortSHA)\(buildContext)"
        case .syncing:
            if let detail, !detail.isEmpty {
                return "Syncing \(shortSHA)\(buildContext): \(detail)"
            }
            return "Syncing \(shortSHA)\(buildContext)"
        case .planningRelease:
            return "Planning release for \(shortSHA)\(buildContext)"
        case .archiving:
            return "Archiving app for \(shortSHA)\(buildContext)"
        case .notarizing:
            return "\(ShipHookLocale.notarising) app for \(shortSHA)\(buildContext)"
        case .publishing:
            return "Publishing update for \(shortSHA)\(buildContext)"
        }
    }

    private func buildContextSuffix(for repositoryID: String) -> String {
        guard let version = buildVersionsInFlight[repositoryID] else {
            return ""
        }
        let marketing = version.marketingVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = version.buildVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if marketing.isEmpty && build.isEmpty {
            return ""
        }
        if build.isEmpty {
            return " (\(marketing))"
        }
        if marketing.isEmpty {
            return " (build \(build))"
        }
        return " (\(marketing) • build \(build))"
    }

    private func appendLog(_ chunk: String, for repositoryID: String) {
        logBuffers[repositoryID, default: ""].append(chunk)
        guard logFlushTasks[repositoryID] == nil else {
            return
        }

        logFlushTasks[repositoryID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.flushLogBuffer(for: repositoryID)
            self?.logFlushTasks.removeValue(forKey: repositoryID)
        }
    }

    private func flushLogBuffer(for repositoryID: String) {
        guard let chunk = logBuffers[repositoryID], !chunk.isEmpty else {
            return
        }
        logBuffers[repositoryID] = ""
        updateState(for: repositoryID) {
            $0.lastLog = tailLines(from: $0.lastLog + chunk, limit: 120)
        }
    }

    private func tailLines(from string: String, limit: Int) -> String {
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(limit).map(String.init).joined(separator: "\n")
    }

    private func startNextQueuedBuildIfPossible() {
        guard activeBuildRepositoryID == nil,
              let nextID = queuedBuildOrder.first,
              let next = queuedBuilds[nextID] else {
            return
        }

        queuedBuilds.removeValue(forKey: nextID)
        queuedBuildOrder.removeFirst()
        Task {
            await check(repository: next.repository, force: true)
        }
    }

    private func shouldIgnore(snapshot: GitHubBranchSnapshot) -> Bool {
        let message = snapshot.message.lowercased()
        return ignoredCommitMarkers.contains(where: { message.contains($0) })
    }

    nonisolated private static func resolveGitCommitAuthor(checkoutPath: String, sha: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "git",
            "-C",
            checkoutPath,
            "show",
            "-s",
            "--format=%an <%ae>",
            sha
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    private func releaseChannel(for snapshot: GitHubBranchSnapshot) -> ReleaseChannel {
        let lowercasedMessage = snapshot.message.lowercased()
        let betaMarkers = ["[beta]", "[shiphook beta]", "[pre-release]", "[prerelease]"]
        return betaMarkers.contains(where: { lowercasedMessage.contains($0) }) ? .beta : .stable
    }

    private func handleFailure(
        for repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot?,
        error: Error,
        summary: String,
        incrementsFailureStreak: Bool
    ) {
        var streak = consecutiveBuildFailures[repository.id] ?? 0
        if incrementsFailureStreak {
            streak += 1
            consecutiveBuildFailures[repository.id] = streak
        }

        let autoPauseThreshold = max(1, configuration.autoPauseFailureCount)
        let shouldAutoPause = incrementsFailureStreak && streak >= autoPauseThreshold
        if shouldAutoPause {
            setRepositoryEnabled(repository.id, enabled: false)
            persistConfigurationQuietly()
        }

        updateState(for: repository.id) {
            $0.activity = .failed
            $0.buildStartedAt = nil
            $0.buildPhase = .idle
            $0.lastError = error.localizedDescription
            if let snapshot {
                $0.releaseChannel = releaseChannel(for: snapshot)
            }
            if $0.lastLog.isEmpty {
                $0.lastLog = error.localizedDescription
            }
            if shouldAutoPause {
                $0.summary = "Build paused after \(streak) consecutive failures. Last error: \(error.localizedDescription)"
            } else {
                $0.summary = summary
            }
        }

        postFailureDiscordWebhookIfNeeded(
            repository: repository,
            snapshot: snapshot,
            error: error,
            failureCount: streak,
            autoPaused: shouldAutoPause
        )

        if shouldAutoPause {
            postAutoPauseDiscordWebhookIfNeeded(
                repository: repository,
                snapshot: snapshot,
                error: error,
                failureCount: streak
            )
        }
    }

    private func setRepositoryEnabled(_ repositoryID: String, enabled: Bool) {
        guard let index = configuration.repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }
        configuration.repositories[index].isEnabled = enabled
    }

    private func persistConfigurationQuietly() {
        do {
            try configStore.saveConfiguration(configuration)
            lastSavedConfiguration = configuration
            refreshDirtyState()
            lastGlobalError = nil
        } catch {
            lastGlobalError = error.localizedDescription
        }
    }

    private func updateState(for repositoryID: String, mutate: (inout RepositoryRuntimeState) -> Void) {
        var state = repoStates[repositoryID] ?? .initial(id: repositoryID)
        mutate(&state)
        repoStates[repositoryID] = state
    }

    private func loadBuildHistory() {
        do {
            buildHistory = try buildHistoryStore.loadHistory().sorted { $0.builtAt > $1.builtAt }
            rebuildBuildHistoryIndex()
        } catch {
            buildHistory = []
            buildHistoryByRepository = [:]
            latestBuildByRepository = [:]
            lastGlobalError = error.localizedDescription
        }
    }

    private func appendBuildRecord(_ record: BuildRecord) {
        buildHistory.insert(record, at: 0)
        var records = buildHistoryByRepository[record.repositoryID] ?? []
        records.insert(record, at: 0)
        buildHistoryByRepository[record.repositoryID] = records
        latestBuildByRepository[record.repositoryID] = records.first
        do {
            try buildHistoryStore.saveHistory(buildHistory)
        } catch {
            lastGlobalError = error.localizedDescription
        }
    }

    private func rebuildBuildHistoryIndex() {
        var grouped: [String: [BuildRecord]] = [:]
        for record in buildHistory {
            grouped[record.repositoryID, default: []].append(record)
        }

        for key in grouped.keys {
            grouped[key]?.sort { $0.builtAt > $1.builtAt }
        }

        buildHistoryByRepository = grouped
        latestBuildByRepository = grouped.compactMapValues { $0.first }
    }

    private func pruneGeneratedData(for repository: RepositoryConfiguration) {
        let retentionCount = max(1, configuration.generatedDataRetentionCount)
        let checkoutPath = (repository.localCheckoutPath as NSString).expandingTildeInPath
        let appName = (repository.xcode?.appName.isEmpty == false ? repository.xcode?.appName : repository.name) ?? repository.name
        let fileManager = FileManager.default

        do {
            try pruneItems(
                atDirectory: "\(checkoutPath)/.shiphook/release-notes",
                retentionCount: retentionCount,
                include: { item in
                    item.lastPathComponent.hasPrefix("\(repository.id)-") && item.pathExtension.lowercased() == "html"
                }
            )

            try pruneItems(
                atDirectory: "\(checkoutPath)/.shiphook/logs",
                retentionCount: retentionCount,
                include: { item in
                    item.lastPathComponent.hasPrefix("\(repository.id)-") && item.pathExtension.lowercased() == "log"
                }
            )

            try pruneItems(
                atDirectory: "\(checkoutPath)/.shiphook/notarization",
                retentionCount: retentionCount,
                include: { item in
                    let name = item.lastPathComponent
                    return name.hasSuffix("-notary.zip")
                        || (!appName.isEmpty && name.hasPrefix(appName) && name.hasSuffix(".zip"))
                }
            )

            try pruneItems(
                atDirectory: "\(checkoutPath)/.shiphook/archive",
                retentionCount: retentionCount,
                include: { $0.pathExtension.lowercased() == "xcarchive" }
            )

            try pruneItems(
                atDirectory: "\(checkoutPath)/release-artifacts",
                retentionCount: retentionCount,
                include: { item in
                    let name = item.lastPathComponent
                    let ext = item.pathExtension.lowercased()
                    guard ["zip", "dmg", "pkg"].contains(ext) else {
                        return false
                    }
                    if appName.isEmpty {
                        return true
                    }
                    return name.hasPrefix(appName + "-") || name.hasPrefix(appName + "_")
                }
            )

            try pruneXcodeArchivesIfNeeded(for: repository, appName: appName, retentionCount: retentionCount, fileManager: fileManager)
        } catch {
            lastGlobalError = "Cleanup warning for \(repository.name): \(error.localizedDescription)"
        }
    }

    private func pruneItems(
        atDirectory directoryPath: String,
        retentionCount: Int,
        include: (URL) -> Bool
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryPath) else {
            return
        }

        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let matching = urls.filter(include)
        let sorted = matching.sorted { lhs, rhs in
            modificationDate(for: lhs) > modificationDate(for: rhs)
        }

        guard sorted.count > retentionCount else {
            return
        }

        for url in sorted.dropFirst(retentionCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func pruneXcodeArchivesIfNeeded(
        for repository: RepositoryConfiguration,
        appName: String,
        retentionCount: Int,
        fileManager: FileManager
    ) throws {
        guard let archivePath = repository.xcode?.archivePath, !archivePath.isEmpty else {
            return
        }

        let expandedArchivePath = (archivePath as NSString).expandingTildeInPath
        let archivesRoot = ("~/Library/Developer/Xcode/Archives" as NSString).expandingTildeInPath
        guard expandedArchivePath.hasPrefix(archivesRoot), !appName.isEmpty else {
            return
        }

        let rootURL = URL(fileURLWithPath: archivesRoot, isDirectory: true)
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }

        var matchingArchives: [URL] = []
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "xcarchive" else {
                continue
            }
            let name = item.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("\(appName) ") else {
                continue
            }
            matchingArchives.append(item)
        }

        let sorted = matchingArchives.sorted { lhs, rhs in
            modificationDate(for: lhs) > modificationDate(for: rhs)
        }

        guard sorted.count > retentionCount else {
            return
        }

        for url in sorted.dropFirst(retentionCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func githubToken(for repository: RepositoryConfiguration) -> String? {
        if let inlineToken = configuration.githubToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inlineToken.isEmpty {
            return inlineToken
        }

        let tokenEnvVar = repository.githubTokenEnvVar ?? configuration.githubTokenEnvVar
        return tokenEnvVar.flatMap { ProcessInfo.processInfo.environment[$0] }
    }

    private nonisolated static func performReleaseRollback(
        repository: RepositoryConfiguration,
        release: GitHubReleaseSummary,
        token: String?,
        githubAPI: GitHubAPI
    ) async throws -> String {
        guard let token, !token.isEmpty else {
            throw NSError(
                domain: "ShipHook",
                code: 900,
                userInfo: [NSLocalizedDescriptionKey: "A GitHub token is required to roll back releases. Configure your token environment variable in Settings."]
            )
        }

        let checkoutPath = (repository.localCheckoutPath as NSString).expandingTildeInPath
        let channel: ReleaseChannel = release.isBeta ? .beta : .stable
        let docsRoot = "\(checkoutPath)/docs"
        let appcastPath = channel == .beta ? "\(docsRoot)/beta/appcast.xml" : "\(docsRoot)/appcast.xml"
        let releaseNotesPath = channel == .beta
            ? "\(docsRoot)/beta/release-notes/\(release.versionLabel).html"
            : "\(docsRoot)/release-notes/\(release.versionLabel).html"

        let commandRunner = ShellCommandRunner()
        _ = try commandRunner.run("git -C '\(checkoutPath)' fetch origin '\(repository.branch)' --tags", currentDirectory: checkoutPath, environment: [:])
        _ = try commandRunner.run("git -C '\(checkoutPath)' checkout '\(repository.branch)'", currentDirectory: checkoutPath, environment: [:])
        _ = try commandRunner.run("git -C '\(checkoutPath)' pull --ff-only origin '\(repository.branch)'", currentDirectory: checkoutPath, environment: [:])

        guard FileManager.default.fileExists(atPath: appcastPath) else {
            throw NSError(
                domain: "ShipHook",
                code: 901,
                userInfo: [NSLocalizedDescriptionKey: "Could not find appcast file at \(appcastPath)."]
            )
        }

        let originalAppcast = try String(contentsOfFile: appcastPath, encoding: .utf8)
        let updatedAppcast = removeReleaseItemFromAppcast(
            originalAppcast,
            version: release.versionLabel,
            tagName: release.tagName
        )

        guard updatedAppcast != originalAppcast else {
            throw NSError(
                domain: "ShipHook",
                code: 902,
                userInfo: [NSLocalizedDescriptionKey: "Could not find release \(release.tagName) in \(URL(fileURLWithPath: appcastPath).lastPathComponent)."]
            )
        }

        try updatedAppcast.write(toFile: appcastPath, atomically: true, encoding: String.Encoding.utf8)
        if FileManager.default.fileExists(atPath: releaseNotesPath) {
            try? FileManager.default.removeItem(atPath: releaseNotesPath)
        }

        var gitTargets = [appcastPath]
        gitTargets.append(releaseNotesPath)
        let quotedTargets = gitTargets.map { "'\($0)'" }.joined(separator: " ")
        _ = try commandRunner.run("git -C '\(checkoutPath)' add -- \(quotedTargets)", currentDirectory: checkoutPath, environment: [:])
        _ = try commandRunner.run("git -C '\(checkoutPath)' add -u -- \(quotedTargets)", currentDirectory: checkoutPath, environment: [:])

        let staged = try commandRunner
            .run("git -C '\(checkoutPath)' diff --cached --name-only -- \(quotedTargets)", currentDirectory: checkoutPath, environment: [:])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if staged.isEmpty {
            throw NSError(
                domain: "ShipHook",
                code: 903,
                userInfo: [NSLocalizedDescriptionKey: "No appcast changes were staged for rollback."]
            )
        }

        let channelPrefix = channel == .beta ? "beta " : ""
        let commitMessage = "chore(shiphook): rollback \(channelPrefix)release \(release.versionLabel) [shiphook skip]"
        _ = try commandRunner.run("git -C '\(checkoutPath)' commit -m '\(commitMessage)'", currentDirectory: checkoutPath, environment: [:])
        _ = try commandRunner.run("git -C '\(checkoutPath)' push origin '\(repository.branch)'", currentDirectory: checkoutPath, environment: [:])

        try await githubAPI.deleteRelease(
            owner: repository.owner,
            repo: repository.repo,
            releaseID: release.id,
            token: token
        )
        try await githubAPI.deleteTagReference(
            owner: repository.owner,
            repo: repository.repo,
            tagName: release.tagName,
            token: token
        )

        return "Rolled back \(release.tagName) on the \(channel.rawValue) channel."
    }

    private nonisolated static func removeReleaseItemFromAppcast(_ appcast: String, version: String, tagName: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?s)<item>.*?</item>", options: []) else {
            return appcast
        }

        let ns = appcast as NSString
        let matches = regex.matches(in: appcast, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            return appcast
        }

        let normalizedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotedTag = "/\(tagName)/"
        let updated = NSMutableString(string: appcast)
        var removed = false

        for match in matches.reversed() {
            let item = ns.substring(with: match.range)
            let hasVersion = item.contains("<sparkle:shortVersionString>\(normalizedVersion)</sparkle:shortVersionString>")
                || item.contains("<title>\(normalizedVersion)</title>")
            let hasTag = item.contains(quotedTag)

            if hasVersion || hasTag {
                updated.replaceCharacters(in: match.range, with: "")
                removed = true
                break
            }
        }

        guard removed else {
            return appcast
        }

        return String(updated)
    }

    private func refreshPublishedVersions() {
        let repositories = configuration.repositories
        Task.detached(priority: .utility) { [releasePlanner] in
            var versions: [String: AppcastVersion] = [:]

            for repository in repositories {
                guard let inspection = try? releasePlanner.inspectReleaseState(for: repository),
                      let latest = inspection.latestAppcastItem else {
                    continue
                }
                versions[repository.id] = latest
            }

            let resolvedVersions = versions

            await MainActor.run {
                self.latestPublishedVersions = resolvedVersions
            }
        }
    }

    private func synchronizeRuntimeState() {
        let validIDs = Set(configuration.repositories.map(\.id))
        repoStates = repoStates.filter { validIDs.contains($0.key) }
        configuration.repositories.forEach { repo in
            repoStates[repo.id] = repoStates[repo.id] ?? .initial(id: repo.id)
        }
    }

    private func postFailureDiscordWebhookIfNeeded(
        repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot?,
        error: Error,
        failureCount: Int,
        autoPaused: Bool
    ) {
        guard let notifications = repository.notifications,
              notifications.postOnFailure,
              let webhookURL = notifications.discordWebhookURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !webhookURL.isEmpty else {
            return
        }
        guard let url = URL(string: webhookURL) else {
            appendLog("Skipping Discord failure webhook: invalid URL.\n", for: repository.id)
            return
        }

        let fields: [[String: Any]] = [
            ["name": "Repository", "value": "\(repository.owner)/\(repository.repo)", "inline": true],
            ["name": "Commit", "value": snapshot.map { String($0.sha.prefix(7)) } ?? "N/A", "inline": true],
            ["name": "Branch", "value": repository.branch, "inline": true],
            ["name": "Failure Count", "value": String(max(1, failureCount)), "inline": true],
            ["name": "Auto-paused", "value": autoPaused ? "Yes" : "No", "inline": true],
            ["name": "Error", "value": error.localizedDescription, "inline": false],
        ]
        let embed: [String: Any] = [
            "title": "\(repository.name) build failed",
            "description": snapshot?.message.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Build failed",
            "url": snapshot?.htmlURL?.absoluteString ?? "",
            "color": 15_704_317,
            "fields": fields,
        ]
        let payload: [String: Any] = [
            "content": "ShipHook failure for **\(repository.name)**: \(autoPaused ? "Build paused" : "Build failed").",
            "embeds": [embed],
        ]
        sendDiscordWebhook(url: url, payload: payload, repositoryIDForLogging: repository.id, successLogLine: "Posted Discord failure webhook notification.\n")
    }

    private func postAutoPauseDiscordWebhookIfNeeded(
        repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot?,
        error: Error,
        failureCount: Int
    ) {
        guard let notifications = repository.notifications,
              notifications.postOnFailure,
              let webhookURL = notifications.discordWebhookURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !webhookURL.isEmpty,
              let url = URL(string: webhookURL) else {
            return
        }

        let fields: [[String: Any]] = [
            ["name": "Repository", "value": "\(repository.owner)/\(repository.repo)", "inline": true],
            ["name": "Branch", "value": repository.branch, "inline": true],
            ["name": "Last Commit", "value": snapshot.map { String($0.sha.prefix(7)) } ?? "N/A", "inline": true],
            ["name": "Last Error", "value": error.localizedDescription, "inline": false],
        ]
        let embed: [String: Any] = [
            "title": "\(repository.name) build paused",
            "description": "Builds paused after \(failureCount) consecutive failures.",
            "url": snapshot?.htmlURL?.absoluteString ?? "",
            "color": 16_667_136,
            "fields": fields,
        ]
        let payload: [String: Any] = [
            "content": "ShipHook paused **\(repository.name)** after repeated failures.",
            "embeds": [embed],
        ]
        sendDiscordWebhook(url: url, payload: payload, repositoryIDForLogging: repository.id, successLogLine: "Posted Discord auto-pause webhook notification.\n")
    }

    private func sendDiscordWebhook(
        url: URL,
        payload: [String: Any],
        repositoryIDForLogging: String? = nil,
        successLogLine: String? = nil
    ) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            if let repositoryIDForLogging {
                appendLog("Skipping Discord webhook: could not encode payload.\n", for: repositoryIDForLogging)
            }
            return
        }

        Task.detached(priority: .utility) {
            var lastFailureLogLine: String?
            var attempt = 0
            while attempt < 2 {
                attempt += 1
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = data

                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse,
                       (200..<300).contains(httpResponse.statusCode) {
                        if let repositoryIDForLogging,
                           let successLogLine {
                            await MainActor.run {
                                self.appendLog(successLogLine, for: repositoryIDForLogging)
                            }
                        }
                        return
                    }
                    if let httpResponse = response as? HTTPURLResponse {
                        lastFailureLogLine = "Discord webhook failed with HTTP \(httpResponse.statusCode).\n"
                    } else {
                        lastFailureLogLine = "Discord webhook failed: no HTTP response.\n"
                    }
                } catch {
                    lastFailureLogLine = "Discord webhook failed: \(error.localizedDescription)\n"
                }

                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(1))
                }
            }

            if let repositoryIDForLogging,
               let lastFailureLogLine {
                await MainActor.run {
                    self.appendLog(lastFailureLogLine, for: repositoryIDForLogging)
                }
            }
        }
    }

    private func makeWebDashboardSnapshot() -> WebDashboardSnapshot {
        let repositories = configuration.repositories.map { repository in
            let state = repoStates[repository.id] ?? .initial(id: repository.id)
            let recentBuilds = Array(history(for: repository.id).prefix(6)).map { record in
                WebDashboardSnapshot.Build(
                    version: record.version,
                    sha: record.sha,
                    builtAt: record.builtAt,
                    releaseChannel: record.releaseChannel?.rawValue,
                    authorLogin: record.authorLogin ?? buildCommitAuthor(for: repository.id, sha: record.sha),
                    authorAvatarURL: (record.authorAvatarURL ?? buildCommitAuthorAvatarURL(for: repository.id, sha: record.sha))?.absoluteString,
                    authorProfileURL: (record.authorProfileURL ?? buildCommitAuthorProfileURL(for: repository.id, sha: record.sha))?.absoluteString,
                    summary: record.summary,
                    logPath: record.logPath
                )
            }
            let recentReleases = Array((releasesByRepository[repository.id] ?? []).prefix(20)).map { release in
                WebDashboardSnapshot.Release(
                    tagName: release.tagName,
                    name: release.name,
                    body: release.body,
                    isPrerelease: release.isPrerelease,
                    publishedAt: release.publishedAt,
                    htmlURL: release.htmlURL?.absoluteString,
                    authorLogin: release.author?.login,
                    authorAvatarURL: release.author?.avatarURL?.absoluteString,
                    authorProfileURL: release.author?.profileURL?.absoluteString
                )
            }
            let latestBuild = recentBuilds.first

            return WebDashboardSnapshot.Repository(
                id: repository.id,
                name: repository.name,
                iconDataURL: webRepositoryIconDataURL(for: repository),
                isEnabled: repository.isEnabled,
                slug: "\(repository.owner)/\(repository.repo)",
                branch: repository.branch,
                activity: state.activity.rawValue,
                phase: state.buildPhase.rawValue,
                summary: state.summary,
                releaseChannel: state.releaseChannel?.rawValue ?? latestBuild?.releaseChannel,
                version: displayedVersion(for: repository),
                publishedVersion: publishedVersion(for: repository),
                lastSeenSHA: state.lastSeenSHA,
                lastBuiltSHA: state.lastBuiltSHA ?? latestBuild?.sha,
                lastCheckDate: state.lastCheckDate,
                lastSuccessDate: state.lastSuccessDate ?? latestBuild?.builtAt,
                buildStartedAt: state.buildStartedAt,
                latestBuild: latestBuild,
                recentBuilds: recentBuilds,
                recentReleases: recentReleases,
                progress: progressSnapshot(for: state),
                lastCommitAuthorLogin: state.lastCommitAuthorLogin,
                lastCommitAuthorAvatarURL: state.lastCommitAuthorAvatarURL?.absoluteString,
                lastCommitAuthorProfileURL: state.lastCommitAuthorProfileURL?.absoluteString
            )
        }

        return WebDashboardSnapshot(
            generatedAt: Date(),
            repositories: repositories
        )
    }

    private func progressSnapshot(for state: RepositoryRuntimeState) -> WebDashboardSnapshot.Progress? {
        let steps = progressStep(for: state.buildPhase)
        guard let steps else {
            return nil
        }

        return WebDashboardSnapshot.Progress(
            currentStep: steps.current,
            totalSteps: steps.total,
            label: steps.label,
            fractionComplete: Double(steps.current) / Double(steps.total)
        )
    }

    private func progressStep(for phase: RepositoryBuildPhase) -> (current: Int, total: Int, label: String)? {
        switch phase {
        case .idle:
            return nil
        case .queued:
            return (1, 5, "Queued")
        case .syncing:
            return (2, 5, "Syncing")
        case .planningRelease:
            return (3, 5, "Planning Release")
        case .archiving:
            return (4, 5, "Archiving")
        case .notarizing:
            return (5, 6, ShipHookLocale.notarising)
        case .publishing:
            return (6, 6, "Publishing")
        }
    }

    private func webRepositoryIconDataURL(for repository: RepositoryConfiguration) -> String? {
        if let cached = webIconDataByRepositoryID[repository.id] {
            return cached
        }

        let icon = resolveWebRepositoryIcon(for: repository)
        guard let dataURL = Self.pngDataURL(from: icon) else {
            return nil
        }
        webIconDataByRepositoryID[repository.id] = dataURL
        return dataURL
    }

    private func resolveWebRepositoryIcon(for repository: RepositoryConfiguration) -> NSImage {
        let fileManager = FileManager.default

        if let artifactPath = repository.xcode?.artifactPath {
            let expandedPath = (artifactPath as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedPath) {
                return NSWorkspace.shared.icon(forFile: expandedPath)
            }
        }

        let checkoutPath = (repository.localCheckoutPath as NSString).expandingTildeInPath
        if fileManager.fileExists(atPath: checkoutPath) {
            return NSWorkspace.shared.icon(forFile: checkoutPath)
        }

        if let projectPath = repository.xcode?.projectPath {
            let expandedProjectPath = (projectPath as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedProjectPath) {
                return NSWorkspace.shared.icon(forFile: expandedProjectPath)
            }
        }

        if let workspacePath = repository.xcode?.workspacePath {
            let expandedWorkspacePath = (workspacePath as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedWorkspacePath) {
                return NSWorkspace.shared.icon(forFile: expandedWorkspacePath)
            }
        }

        if #available(macOS 12.0, *) {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }

    nonisolated private static func pngDataURL(from image: NSImage) -> String? {
        let targetSize = NSSize(width: 48, height: 48)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }
}
