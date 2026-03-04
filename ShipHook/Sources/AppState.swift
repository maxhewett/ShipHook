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
    @Published private(set) var latestPublishedVersions: [String: AppcastVersion] = [:]
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
    private var pollingTask: Task<Void, Never>?
    private var inFlightBuilds: Set<String> = []
    private var queuedBuilds: [String: (repository: RepositoryConfiguration, snapshot: GitHubBranchSnapshot)] = [:]
    private var queuedBuildOrder: [String] = []
    private var activeBuildRepositoryID: String?
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
                skipIfVersionIsNotNewer: true
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
        buildHistory
            .filter { $0.repositoryID == repositoryID }
            .sorted { $0.builtAt > $1.builtAt }
    }

    func latestBuildRecord(for repositoryID: String) -> BuildRecord? {
        history(for: repositoryID).first
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
        configuration.repositories = configuration.repositories.map { repository in
            var repository = repository
            if var xcode = repository.xcode {
                xcode.workspacePath = xcode.sanitizedWorkspacePath
                repository.xcode = xcode
            }
            return repository
        }
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
                await checkRepositories(force: false)
                let interval = max(60, configuration.pollIntervalSeconds)
                try? await Task.sleep(for: .seconds(interval))
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
                $0.summary = "Repository is disabled"
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
            let tokenEnvVar = repository.githubTokenEnvVar ?? configuration.githubTokenEnvVar
            let token = tokenEnvVar.flatMap { ProcessInfo.processInfo.environment[$0] }
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
            }

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
                updateState(for: repository.id) {
                    $0.summary = "Build already in progress"
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
                }
                return
            }

            inFlightBuilds.insert(repository.id)
            activeBuildRepositoryID = repository.id
            updateState(for: repository.id) {
                $0.activity = .building
                $0.buildStartedAt = Date()
                $0.buildPhase = .syncing
                $0.summary = "Building commit \(snapshot.sha.prefix(7))"
                $0.lastLogPath = "\((repository.localCheckoutPath as NSString).expandingTildeInPath)/.shiphook/logs/\(repository.id)-latest.log"
                $0.lastLog = ""
            }

            let runner = pipelineRunner
            Task.detached { [weak self] in
                let result: Result<PipelineOutcome, Error> = Result {
                    try runner.run(repository: repository, snapshot: snapshot, onStageChange: { stage in
                        Task { @MainActor [weak self] in
                            self?.updateBuildStage(stage, for: repository.id, sha: snapshot.sha)
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
            updateState(for: repository.id) {
                $0.activity = .failed
                $0.lastError = error.localizedDescription
                $0.buildPhase = .idle
                $0.summary = "GitHub poll failed: \(error.localizedDescription)"
            }
        }
    }

    private func finishBuild(
        for repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot,
        result: Result<PipelineOutcome, Error>
    ) {
        inFlightBuilds.remove(repository.id)
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
                    $0.lastLog = outcome.log
                    $0.lastLogPath = outcome.logPath
                    $0.lastError = nil
                    $0.summary = outcome.summary
                }
                startNextQueuedBuildIfPossible()
                return
            }
            let historyRecord = BuildRecord(
                id: UUID().uuidString,
                repositoryID: repository.id,
                repositoryName: repository.name,
                version: outcome.version,
                sha: outcome.builtSHA,
                builtAt: Date()
            )
            appendBuildRecord(historyRecord)
            updateState(for: repository.id) {
                $0.activity = .succeeded
                $0.lastBuiltSHA = outcome.builtSHA
                $0.lastSuccessDate = historyRecord.builtAt
                $0.buildStartedAt = nil
                $0.buildPhase = .idle
                $0.lastLog = outcome.log
                $0.lastLogPath = outcome.logPath
                $0.lastError = nil
                $0.summary = outcome.summary
            }
        case let .failure(error):
            updateState(for: repository.id) {
                $0.activity = .failed
                $0.buildStartedAt = nil
                $0.buildPhase = .idle
                $0.lastError = error.localizedDescription
                if $0.lastLog.isEmpty {
                    $0.lastLog = error.localizedDescription
                }
                $0.summary = "Build or publish failed"
            }
            postFailureDiscordWebhookIfNeeded(repository: repository, snapshot: snapshot, error: error)
        }

        startNextQueuedBuildIfPossible()
    }

    private func updateBuildStage(_ stage: PipelineStage, for repositoryID: String, sha: String) {
        updateState(for: repositoryID) {
            $0.activity = .building
            switch stage {
            case let .syncing(message):
                $0.buildPhase = .syncing
                $0.summary = "Syncing \(String(sha.prefix(7))): \(message)"
            case .planningRelease:
                $0.buildPhase = .planningRelease
                $0.summary = "Planning release for \(String(sha.prefix(7)))"
            case .archiving:
                $0.buildPhase = .archiving
                $0.summary = "Archiving app for \(String(sha.prefix(7)))"
            case .notarizing:
                $0.buildPhase = .notarizing
                $0.summary = "\(ShipHookLocale.notarising) app for \(String(sha.prefix(7)))"
            case .publishing:
                $0.buildPhase = .publishing
                $0.summary = "Publishing update for \(String(sha.prefix(7)))"
            }
        }
    }

    private func appendLog(_ chunk: String, for repositoryID: String) {
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

    private func updateState(for repositoryID: String, mutate: (inout RepositoryRuntimeState) -> Void) {
        var state = repoStates[repositoryID] ?? .initial(id: repositoryID)
        mutate(&state)
        repoStates[repositoryID] = state
    }

    private func loadBuildHistory() {
        do {
            buildHistory = try buildHistoryStore.loadHistory().sorted { $0.builtAt > $1.builtAt }
        } catch {
            buildHistory = []
            lastGlobalError = error.localizedDescription
        }
    }

    private func appendBuildRecord(_ record: BuildRecord) {
        buildHistory.insert(record, at: 0)
        do {
            try buildHistoryStore.saveHistory(buildHistory)
        } catch {
            lastGlobalError = error.localizedDescription
        }
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
        snapshot: GitHubBranchSnapshot,
        error: Error
    ) {
        guard let notifications = repository.notifications,
              notifications.postOnFailure,
              let webhookURL = notifications.discordWebhookURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !webhookURL.isEmpty,
              let url = URL(string: webhookURL) else {
            return
        }

        let payload: [String: Any] = [
            "content": "ShipHook failed to build **\(repository.name)**.",
            "embeds": [[
                "title": "\(repository.name) build failed",
                "description": snapshot.message.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Build failed",
                "url": snapshot.htmlURL?.absoluteString ?? "",
                "color": 15_704_317,
                "fields": [
                    ["name": "Repository", "value": "\(repository.owner)/\(repository.repo)", "inline": true],
                    ["name": "Commit", "value": String(snapshot.sha.prefix(7)), "inline": true],
                    ["name": "Branch", "value": repository.branch, "inline": true],
                    ["name": "Error", "value": error.localizedDescription, "inline": false],
                ],
            ]]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request).resume()
    }

    private func makeWebDashboardSnapshot() -> WebDashboardSnapshot {
        let repositories = configuration.repositories.map { repository in
            let state = repoStates[repository.id] ?? .initial(id: repository.id)
            let recentBuilds = Array(history(for: repository.id).prefix(6)).map { record in
                WebDashboardSnapshot.Build(
                    version: record.version,
                    sha: record.sha,
                    builtAt: record.builtAt
                )
            }
            let latestBuild = recentBuilds.first

            return WebDashboardSnapshot.Repository(
                id: repository.id,
                name: repository.name,
                isEnabled: repository.isEnabled,
                slug: "\(repository.owner)/\(repository.repo)",
                branch: repository.branch,
                activity: state.activity.rawValue,
                phase: state.buildPhase.rawValue,
                summary: state.summary,
                version: displayedVersion(for: repository),
                publishedVersion: publishedVersion(for: repository),
                lastSeenSHA: state.lastSeenSHA,
                lastBuiltSHA: state.lastBuiltSHA,
                lastCheckDate: state.lastCheckDate,
                lastSuccessDate: state.lastSuccessDate,
                buildStartedAt: state.buildStartedAt,
                latestBuild: latestBuild,
                recentBuilds: recentBuilds,
                recentLog: state.lastLog,
                lastLogPath: state.lastLogPath,
                lastError: state.lastError,
                progress: progressSnapshot(for: state)
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
}
