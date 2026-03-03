import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var configuration: AppConfiguration = .default
    @Published private(set) var repoStates: [String: RepositoryRuntimeState] = [:]
    @Published private(set) var configPath: String = ""
    @Published private(set) var lastGlobalError: String?
    @Published private(set) var availableSigningIdentities: [SigningIdentity] = []
    @Published private(set) var lastSigningIdentityError: String?
    @Published private(set) var signingDiagnostics: SigningDiagnostics?

    private var configStore = ConfigStore()
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

    init() {
        loadConfiguration()
        refreshSigningIdentities()
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
            synchronizeRuntimeState()
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
                if repository.signing == nil {
                    repository.signing = .default
                }
                return repository
            }
            try configStore.saveConfiguration(configuration)
            synchronizeRuntimeState()
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
        let checkoutPath = (localCheckoutPath as NSString).expandingTildeInPath
        let safeName = (scheme.isEmpty ? repo : scheme).replacingOccurrences(of: " ", with: "-")
        let archivePath = defaultArchivePath(appName: safeName)
        let appName = scheme.isEmpty ? repo : scheme
        let artifactPath = "\(archivePath)/Products/Applications/\(appName).app"

        return RepositoryConfiguration(
            id: "repo-\(UUID().uuidString.prefix(8).lowercased())",
            name: appName.isEmpty ? repo : appName,
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
            bash "$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT" --version "$SHIPHOOK_VERSION" --artifact "$SHIPHOOK_ARTIFACT_PATH" --app-name "\(appName)" --repo-owner "$SHIPHOOK_GITHUB_OWNER" --repo-name "$SHIPHOOK_GITHUB_REPO" --release-notes "$SHIPHOOK_RELEASE_NOTES_PATH" --docs-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/docs" --releases-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/release-artifacts" --working-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH"
            """,
            releaseNotesPath: inspection.releaseNotesPath,
            githubTokenEnvVar: nil,
            environment: [:],
            versionStrategy: .shortSHATimestamp,
            sparkle: SparkleConfiguration(
                appcastURL: defaultAppcastURL(owner: owner, repo: repo),
                autoIncrementBuild: true
            ),
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
    }

    func triggerManualPoll() {
        Task {
            await checkRepositories(force: true)
        }
    }

    func openConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
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

    private func checkRepositories(force: Bool) async {
        for repository in configuration.repositories {
            await check(repository: repository, force: force)
        }
    }

    private func check(repository: RepositoryConfiguration, force: Bool) async {
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
            updateState(for: repository.id) {
                $0.activity = .succeeded
                $0.lastBuiltSHA = outcome.builtSHA
                $0.lastSuccessDate = Date()
                $0.buildStartedAt = nil
                $0.buildPhase = .idle
                $0.lastLog = outcome.log
                $0.lastLogPath = outcome.logPath
                $0.lastError = nil
                $0.summary = "Published \(outcome.version) from \(snapshot.sha.prefix(7))"
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
                $0.summary = "Notarizing app for \(String(sha.prefix(7)))"
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

    private func synchronizeRuntimeState() {
        let validIDs = Set(configuration.repositories.map(\.id))
        repoStates = repoStates.filter { validIDs.contains($0.key) }
        configuration.repositories.forEach { repo in
            repoStates[repo.id] = repoStates[repo.id] ?? .initial(id: repo.id)
        }
    }
}
