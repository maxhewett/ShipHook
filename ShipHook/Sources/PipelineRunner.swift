import Foundation

struct PipelineOutcome {
    var builtSHA: String
    var version: String
    var artifactPath: String
    var log: String
}

struct PipelineRunner {
    private let commandRunner = ShellCommandRunner()

    func run(repository: RepositoryConfiguration, snapshot: GitHubBranchSnapshot) throws -> PipelineOutcome {
        let workspaceRoot = FileManager.default.currentDirectoryPath
        let checkoutPath = repository.localCheckoutPath.expandingTildeInPath
        let workingDirectory = (repository.workingDirectory ?? checkoutPath).expandingTildeInPath
        let version = makeVersion(for: repository, snapshot: snapshot)
        let bundledPublishScript = Bundle.main.url(forResource: "publish_sparkle_release", withExtension: "sh")?.path ?? ""

        var combinedLog = ""

        let baseEnvironment = repository.environment.merging([
            "SHIPHOOK_WORKSPACE_ROOT": workspaceRoot,
            "SHIPHOOK_REPO_ID": repository.id,
            "SHIPHOOK_REPO_NAME": repository.name,
            "SHIPHOOK_GITHUB_OWNER": repository.owner,
            "SHIPHOOK_GITHUB_REPO": repository.repo,
            "SHIPHOOK_BRANCH": repository.branch,
            "SHIPHOOK_SHA": snapshot.sha,
            "SHIPHOOK_SHORT_SHA": String(snapshot.sha.prefix(7)),
            "SHIPHOOK_VERSION": version,
            "SHIPHOOK_LOCAL_CHECKOUT_PATH": checkoutPath,
            "SHIPHOOK_RELEASE_NOTES_PATH": repository.releaseNotesPath?.expandingTildeInPath ?? "",
            "SHIPHOOK_BUNDLED_PUBLISH_SCRIPT": bundledPublishScript,
        ]) { _, rhs in rhs }

        combinedLog += try syncRepository(repository, checkoutPath: checkoutPath, sha: snapshot.sha)

        let artifactPath: String
        switch repository.buildMode {
        case .xcodeArchive:
            guard let xcode = repository.xcode else {
                throw NSError(domain: "ShipHook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing xcode build configuration for \(repository.name)."])
            }
            let outcome = try runXcodeBuild(xcode, workingDirectory: workingDirectory, environment: baseEnvironment)
            artifactPath = outcome.artifactPath
            combinedLog += outcome.log
        case .shell:
            guard let shell = repository.shell else {
                throw NSError(domain: "ShipHook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing shell build configuration for \(repository.name)."])
            }
            let result = try commandRunner.run(shell.command, currentDirectory: workingDirectory, environment: baseEnvironment)
            combinedLog += result.output
            artifactPath = shell.artifactPath.expandingTildeInPath
        }

        var publishEnvironment = baseEnvironment
        publishEnvironment["SHIPHOOK_ARTIFACT_PATH"] = artifactPath
        let publishResult = try commandRunner.run(repository.publishCommand, currentDirectory: workingDirectory, environment: publishEnvironment)
        combinedLog += publishResult.output

        return PipelineOutcome(
            builtSHA: snapshot.sha,
            version: version,
            artifactPath: artifactPath,
            log: combinedLog
        )
    }

    private func syncRepository(_ repository: RepositoryConfiguration, checkoutPath: String, sha: String) throws -> String {
        let commands = [
            "git -C '\(checkoutPath)' fetch origin '\(repository.branch)' --tags",
            "git -C '\(checkoutPath)' checkout '\(repository.branch)'",
            "git -C '\(checkoutPath)' pull --ff-only origin '\(repository.branch)'",
            "git -C '\(checkoutPath)' checkout '\(sha)'",
        ]

        return try commands.reduce(into: "") { partialResult, command in
            let result = try commandRunner.run(command, currentDirectory: checkoutPath, environment: [:])
            partialResult += result.output
        }
    }

    private func runXcodeBuild(
        _ xcode: XcodeBuildConfiguration,
        workingDirectory: String,
        environment: [String: String]
    ) throws -> (artifactPath: String, log: String) {
        let archivePath = xcode.archivePath.expandingTildeInPath
        let exportPath = xcode.exportPath.expandingTildeInPath
        let exportOptions = xcode.exportOptionsPlistPath.expandingTildeInPath
        let artifactPath = xcode.artifactPath.expandingTildeInPath

        let targetFlag: String
        if let workspacePath = xcode.workspacePath?.expandingTildeInPath, !workspacePath.isEmpty {
            targetFlag = "-workspace '\(workspacePath)'"
        } else if let projectPath = xcode.projectPath?.expandingTildeInPath, !projectPath.isEmpty {
            targetFlag = "-project '\(projectPath)'"
        } else {
            throw NSError(domain: "ShipHook", code: 2, userInfo: [NSLocalizedDescriptionKey: "Either workspacePath or projectPath must be set."])
        }

        let archiveCommand = """
        xcodebuild \(targetFlag) -scheme '\(xcode.scheme)' -configuration '\(xcode.configuration)' archive -archivePath '\(archivePath)'
        """

        let exportCommand = """
        xcodebuild -exportArchive -archivePath '\(archivePath)' -exportPath '\(exportPath)' -exportOptionsPlist '\(exportOptions)'
        """

        let archiveResult = try commandRunner.run(archiveCommand, currentDirectory: workingDirectory, environment: environment)
        let exportResult = try commandRunner.run(exportCommand, currentDirectory: workingDirectory, environment: environment)
        return (artifactPath, archiveResult.output + exportResult.output)
    }

    private func makeVersion(for repository: RepositoryConfiguration, snapshot: GitHubBranchSnapshot) -> String {
        let shortSHA = String(snapshot.sha.prefix(7))
        let date = snapshot.committedAt ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        switch repository.versionStrategy {
        case .shortSHA:
            return shortSHA
        case .shortSHATimestamp:
            formatter.dateFormat = "yyyyMMddHHmm"
            return "\(formatter.string(from: date))-\(shortSHA)"
        case .dateAndShortSHA:
            formatter.dateFormat = "yyyy-MM-dd"
            return "\(formatter.string(from: date))-\(shortSHA)"
        }
    }
}

private extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}
