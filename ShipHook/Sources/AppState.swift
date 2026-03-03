import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var configuration: AppConfiguration = .default
    @Published private(set) var repoStates: [String: RepositoryRuntimeState] = [:]
    @Published private(set) var configPath: String = ""
    @Published private(set) var lastGlobalError: String?

    private var configStore = ConfigStore()
    private let githubAPI = GitHubAPI()
    private let pipelineRunner = PipelineRunner()
    private var pollingTask: Task<Void, Never>?
    private var inFlightBuilds: Set<String> = []

    init() {
        loadConfiguration()
        startPollingLoop()
    }

    deinit {
        pollingTask?.cancel()
    }

    func loadConfiguration() {
        do {
            configuration = try configStore.loadConfiguration()
            configPath = configStore.configURL.path
            configuration.repositories.forEach { repo in
                repoStates[repo.id] = repoStates[repo.id] ?? .initial(id: repo.id)
            }
            lastGlobalError = nil
        } catch {
            lastGlobalError = error.localizedDescription
        }
    }

    func triggerManualPoll() {
        Task {
            await checkRepositories(force: true)
        }
    }

    func openConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
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

            inFlightBuilds.insert(repository.id)
            updateState(for: repository.id) {
                $0.activity = .building
                $0.summary = "Building commit \(snapshot.sha.prefix(7))"
            }

            let runner = pipelineRunner
            Task.detached { [weak self] in
                let result: Result<PipelineOutcome, Error> = Result {
                    try runner.run(repository: repository, snapshot: snapshot)
                }
                await self?.finishBuild(for: repository, snapshot: snapshot, result: result)
            }
        } catch {
            updateState(for: repository.id) {
                $0.activity = .failed
                $0.lastError = error.localizedDescription
                $0.summary = "GitHub poll failed"
            }
        }
    }

    private func finishBuild(
        for repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot,
        result: Result<PipelineOutcome, Error>
    ) {
        inFlightBuilds.remove(repository.id)

        switch result {
        case let .success(outcome):
            updateState(for: repository.id) {
                $0.activity = .succeeded
                $0.lastBuiltSHA = outcome.builtSHA
                $0.lastSuccessDate = Date()
                $0.lastLog = outcome.log
                $0.lastError = nil
                $0.summary = "Published \(outcome.version) from \(snapshot.sha.prefix(7))"
            }
        case let .failure(error):
            updateState(for: repository.id) {
                $0.activity = .failed
                $0.lastError = error.localizedDescription
                $0.summary = "Build or publish failed"
            }
        }
    }

    private func updateState(for repositoryID: String, mutate: (inout RepositoryRuntimeState) -> Void) {
        var state = repoStates[repositoryID] ?? .initial(id: repositoryID)
        mutate(&state)
        repoStates[repositoryID] = state
    }
}
