import Foundation

struct PipelineOutcome {
    var builtSHA: String
    var version: String
    var artifactPath: String
    var log: String
    var logPath: String
}

enum PipelineStage {
    case syncing(String)
    case planningRelease
    case archiving
    case publishing
}

struct PipelineRunner {
    private let commandRunner = ShellCommandRunner()
    private let releasePlanner = ReleasePlanner()
    private let signingInspector = SigningInspector()

    func run(
        repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot,
        onStageChange: ((PipelineStage) -> Void)? = nil,
        onOutput: ((String) -> Void)? = nil
    ) throws -> PipelineOutcome {
        let workspaceRoot = FileManager.default.currentDirectoryPath
        let fileManager = FileManager.default
        let checkoutPath = repository.localCheckoutPath.expandingTildeInPath
        let workingDirectory = (repository.workingDirectory ?? checkoutPath).expandingTildeInPath
        let bundledPublishScript = Bundle.main.url(forResource: "publish_sparkle_release", withExtension: "sh")?.path ?? ""
        let logsDirectory = "\(checkoutPath)/.shiphook/logs"
        let logPath = "\(logsDirectory)/\(repository.id)-latest.log"

        try fileManager.createDirectory(atPath: logsDirectory, withIntermediateDirectories: true, attributes: nil)
        try Data().write(to: URL(fileURLWithPath: logPath))

        var combinedLog = ""
        let appendOutput: (String) -> Void = { chunk in
            combinedLog.append(chunk)
            if let data = chunk.data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
            onOutput?(chunk)
        }

        onStageChange?(.syncing("Fetching latest branch state"))
        try syncRepository(repository, checkoutPath: checkoutPath, sha: snapshot.sha, onStageChange: onStageChange, onOutput: appendOutput)

        onStageChange?(.planningRelease)
        let releasePlan = try releasePlanner.prepareRelease(for: repository)
        let version = releasePlan?.version.marketingVersion ?? makeVersion(for: repository, snapshot: snapshot)
        let buildVersion = releasePlan?.version.buildVersion ?? ""

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
            "SHIPHOOK_BUILD_VERSION": buildVersion,
            "SHIPHOOK_LOCAL_CHECKOUT_PATH": checkoutPath,
            "SHIPHOOK_RELEASE_NOTES_PATH": repository.releaseNotesPath?.expandingTildeInPath ?? "",
            "SHIPHOOK_BUNDLED_PUBLISH_SCRIPT": bundledPublishScript,
            "SHIPHOOK_APPCAST_URL": releasePlan?.appcastURL ?? "",
        ]) { _, rhs in rhs }

        if let releasePlan, releasePlan.appliedBuildMutation {
            combinedLog += "Updated CURRENT_PROJECT_VERSION to \(releasePlan.version.buildVersion) before archive.\n"
        }

        let artifactPath: String
        switch repository.buildMode {
        case .xcodeArchive:
            try signingInspector.validateReleaseSigning(repository.signing)
            guard let xcode = repository.xcode else {
                throw NSError(domain: "ShipHook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing xcode build configuration for \(repository.name)."])
            }
            onStageChange?(.archiving)
            let outcome = try runXcodeBuild(repository: repository, xcode, workingDirectory: workingDirectory, environment: baseEnvironment, onOutput: appendOutput)
            artifactPath = outcome.artifactPath
        case .shell:
            guard let shell = repository.shell else {
                throw NSError(domain: "ShipHook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing shell build configuration for \(repository.name)."])
            }
            onStageChange?(.archiving)
            _ = try commandRunner.run(shell.command, currentDirectory: workingDirectory, environment: baseEnvironment, onOutput: appendOutput)
            artifactPath = shell.artifactPath.expandingTildeInPath
        }

        var publishEnvironment = baseEnvironment
        publishEnvironment["SHIPHOOK_ARTIFACT_PATH"] = artifactPath
        onStageChange?(.publishing)
        _ = try commandRunner.run(repository.publishCommand, currentDirectory: workingDirectory, environment: publishEnvironment, onOutput: appendOutput)

        return PipelineOutcome(
            builtSHA: snapshot.sha,
            version: version,
            artifactPath: artifactPath,
            log: combinedLog,
            logPath: logPath
        )
    }

    private func syncRepository(
        _ repository: RepositoryConfiguration,
        checkoutPath: String,
        sha: String,
        onStageChange: ((PipelineStage) -> Void)?,
        onOutput: ((String) -> Void)?
    ) throws {
        let commands = [
            ("Fetching origin/\(repository.branch)", "git -C '\(checkoutPath)' fetch origin '\(repository.branch)' --tags"),
            ("Checking out branch \(repository.branch)", "git -C '\(checkoutPath)' checkout '\(repository.branch)'"),
            ("Fast-forwarding branch \(repository.branch)", "git -C '\(checkoutPath)' pull --ff-only origin '\(repository.branch)'"),
            ("Verifying local HEAD", "git -C '\(checkoutPath)' rev-parse HEAD"),
        ]

        try commands.forEach { item in
            onStageChange?(.syncing(item.0))
            _ = try commandRunner.run(item.1, currentDirectory: checkoutPath, environment: [:], onOutput: onOutput)
        }

        let currentHead = try commandRunner
            .run("git -C '\(checkoutPath)' rev-parse HEAD", currentDirectory: checkoutPath, environment: [:])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentHead == sha else {
            throw NSError(
                domain: "ShipHook",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Repository HEAD \(currentHead) does not match GitHub snapshot \(sha) after sync."]
            )
        }
    }

    private func runXcodeBuild(
        repository: RepositoryConfiguration,
        _ xcode: XcodeBuildConfiguration,
        workingDirectory: String,
        environment: [String: String],
        onOutput: ((String) -> Void)?
    ) throws -> (artifactPath: String, log: String) {
        let fileManager = FileManager.default
        let archivePath = xcode.archivePath.expandingTildeInPath
        let artifactPath = xcode.artifactPath.expandingTildeInPath
        let derivedDataPath = "\(repository.localCheckoutPath.expandingTildeInPath)/.shiphook/derived-data/\(repository.id)"

        try fileManager.createDirectory(
            at: URL(fileURLWithPath: archivePath).deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: derivedDataPath),
            withIntermediateDirectories: true,
            attributes: nil
        )

        let targetFlag: String
        if let workspacePath = xcode.sanitizedWorkspacePath?.expandingTildeInPath, !workspacePath.isEmpty {
            targetFlag = "-workspace '\(workspacePath)'"
        } else if let projectPath = xcode.projectPath?.expandingTildeInPath, !projectPath.isEmpty {
            targetFlag = "-project '\(projectPath)'"
        } else {
            throw NSError(domain: "ShipHook", code: 2, userInfo: [NSLocalizedDescriptionKey: "Either workspacePath or projectPath must be set."])
        }

        let archiveCommand = """
        xcodebuild \(targetFlag) -scheme '\(xcode.scheme)' -configuration '\(xcode.configuration)' -derivedDataPath '\(derivedDataPath)' archive -archivePath '\(archivePath)'\(signingOverrides(for: repository))
        """

        let archiveResult = try commandRunner.run(archiveCommand, currentDirectory: workingDirectory, environment: environment, onOutput: onOutput)
        return (artifactPath, archiveResult.output)
    }

    private func signingOverrides(for repository: RepositoryConfiguration) -> String {
        guard let signing = repository.signing else {
            return ""
        }

        var parts: [String] = []
        parts.append(" CODE_SIGN_STYLE=\(signing.codeSignStyle.rawValue.capitalized)")
        if let team = signing.developmentTeam, !team.isEmpty {
            parts.append(" DEVELOPMENT_TEAM='\(team)'")
        }
        if signing.codeSignStyle == .manual,
           let identity = signing.codeSignIdentity,
           !identity.isEmpty {
            parts.append(" CODE_SIGN_IDENTITY='\(identity)'")
        }
        return parts.joined()
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
