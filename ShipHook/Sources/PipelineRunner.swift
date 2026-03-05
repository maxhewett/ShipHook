import Foundation

struct PipelineOutcome {
    var builtSHA: String
    var version: String
    var artifactPath: String
    var log: String
    var logPath: String
    var skippedPublish: Bool
    var summary: String
    var releaseChannel: ReleaseChannel
}

private struct ReleaseNotesSource {
    var sha: String
    var title: String
    var message: String
    var commitURL: URL?
}

enum NotarizationError: LocalizedError {
    case invalidSubmission(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSubmission(message):
            return message
        }
    }
}

enum PipelineStage {
    case syncing(String)
    case planningRelease
    case archiving
    case notarizing
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
        onVersionResolved: ((AppVersion) -> Void)? = nil,
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
        let synchronizedSHA = try syncRepository(repository, checkoutPath: checkoutPath, sha: snapshot.sha, onStageChange: onStageChange, onOutput: appendOutput)
        let effectiveSnapshot = try resolvedSynchronizedSnapshot(
            for: repository,
            checkoutPath: checkoutPath,
            fallback: snapshot,
            synchronizedSHA: synchronizedSHA
        )

        let releaseNotesSource = try resolvedReleaseNotesSource(
            for: repository,
            snapshot: effectiveSnapshot,
            checkoutPath: checkoutPath
        )

        onStageChange?(.planningRelease)
        let snapshotChannel = requestedReleaseChannel(
            snapshotMessage: effectiveSnapshot.message,
            releaseNotesMessage: releaseNotesSource.message
        )
        var releasePlan = try releasePlanner.prepareRelease(for: repository, channel: snapshotChannel)
        var resolvedVersion = AppVersion(
            marketingVersion: releasePlan?.version.marketingVersion ?? makeVersion(for: repository, snapshot: effectiveSnapshot),
            buildVersion: releasePlan?.version.buildVersion ?? ""
        )
        let releaseChannel = resolvedReleaseChannel(requestedChannel: snapshotChannel, version: resolvedVersion)
        if releaseChannel != snapshotChannel {
            try? releasePlanner.restoreProjectVersionIfNeeded(releasePlan, xcode: repository.xcode)
            releasePlan = try releasePlanner.prepareRelease(for: repository, channel: releaseChannel)
            resolvedVersion = AppVersion(
                marketingVersion: releasePlan?.version.marketingVersion ?? makeVersion(for: repository, snapshot: effectiveSnapshot),
                buildVersion: releasePlan?.version.buildVersion ?? ""
            )
        }
        defer {
            try? releasePlanner.restoreProjectVersionIfNeeded(releasePlan, xcode: repository.xcode)
        }

        let version = resolvedVersion.marketingVersion
        let buildVersion = resolvedVersion.buildVersion
        onVersionResolved?(resolvedVersion)
        let releaseNotesPath = try resolvedReleaseNotesPath(
            for: repository,
            releaseNotesSource: releaseNotesSource,
            checkoutPath: checkoutPath,
            version: version
        )

        let baseEnvironment = repository.environment.merging([
            "SHIPHOOK_WORKSPACE_ROOT": workspaceRoot,
            "SHIPHOOK_REPO_ID": repository.id,
            "SHIPHOOK_REPO_NAME": repository.name,
            "SHIPHOOK_GITHUB_OWNER": repository.owner,
            "SHIPHOOK_GITHUB_REPO": repository.repo,
            "SHIPHOOK_BRANCH": repository.branch,
            "SHIPHOOK_SHA": effectiveSnapshot.sha,
            "SHIPHOOK_SHORT_SHA": String(effectiveSnapshot.sha.prefix(7)),
            "SHIPHOOK_VERSION": version,
            "SHIPHOOK_BUILD_VERSION": buildVersion,
            "SHIPHOOK_RELEASE_CHANNEL": releaseChannel.rawValue,
            "SHIPHOOK_LOCAL_CHECKOUT_PATH": checkoutPath,
            "SHIPHOOK_RELEASE_NOTES_PATH": releaseNotesPath,
            "SHIPHOOK_BUNDLED_PUBLISH_SCRIPT": bundledPublishScript,
            "SHIPHOOK_APPCAST_URL": releasePlan?.appcastURL ?? "",
        ]) { _, rhs in rhs }

        if let releasePlan, releasePlan.appliedBuildMutation {
            combinedLog += "Updated CURRENT_PROJECT_VERSION to \(releasePlan.version.buildVersion) before archive.\n"
        }
        if releaseChannel == .beta {
            combinedLog += "Detected beta release channel from commit/release-notes markers.\n"
        }
        if let releasePlan, releasePlan.shouldSkipPublish {
            let summary = releasePlan.skipReason ?? "Skipped publish because the app version is not newer than the current appcast item."
            combinedLog += "\(summary)\n"
            return PipelineOutcome(
                builtSHA: effectiveSnapshot.sha,
                version: version,
                artifactPath: "",
                log: combinedLog,
                logPath: logPath,
                skippedPublish: true,
                summary: summary,
                releaseChannel: releaseChannel
            )
        }

        let restoreBetaSourceIconIfNeeded = try prepareBetaSourceIconOverrideIfNeeded(
            repository: repository,
            releaseChannel: releaseChannel,
            checkoutPath: checkoutPath,
            onOutput: appendOutput
        )
        defer {
            do {
                try restoreBetaSourceIconIfNeeded?()
            } catch {
                appendOutput("Warning: failed to restore source icon override: \(error.localizedDescription)\n")
            }
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

        try applyBetaIconIfNeeded(
            artifactPath: artifactPath,
            repository: repository,
            releaseChannel: releaseChannel,
            checkoutPath: checkoutPath,
            onOutput: appendOutput
        )
        try applyReleaseChannelMetadata(
            artifactPath: artifactPath,
            releaseChannel: releaseChannel,
            onOutput: appendOutput
        )
        let expectedTeamID = repository.signing?.developmentTeam
        try normalizeCodeSigningIfNeeded(
            artifactPath: artifactPath,
            repository: repository,
            checkoutPath: checkoutPath,
            onOutput: appendOutput
        )
        try signingInspector.verifyBuiltApp(at: artifactPath, expectedTeamID: expectedTeamID)
        try notarizeAndStapleAppIfNeeded(
            artifactPath: artifactPath,
            repository: repository,
            checkoutPath: checkoutPath,
            onStageChange: onStageChange,
            onOutput: appendOutput
        )

        var publishEnvironment = baseEnvironment
        publishEnvironment["SHIPHOOK_ARTIFACT_PATH"] = artifactPath
        onStageChange?(.publishing)
        _ = try commandRunner.run(repository.publishCommand, currentDirectory: workingDirectory, environment: publishEnvironment, onOutput: appendOutput)
        try verifyPublishedAppcast(
            repository: repository,
            checkoutPath: checkoutPath,
            releaseChannel: releaseChannel,
            expectedMarketingVersion: version,
            expectedBuildVersion: buildVersion
        )
        postDiscordWebhookIfNeeded(
            repository: repository,
            snapshot: effectiveSnapshot,
            version: version,
            releaseChannel: releaseChannel,
            appcastURL: releasePlan?.appcastURL,
            artifactPath: artifactPath,
            releaseNotesSource: releaseNotesSource,
            onOutput: appendOutput
        )

        return PipelineOutcome(
            builtSHA: effectiveSnapshot.sha,
            version: version,
            artifactPath: artifactPath,
            log: combinedLog,
            logPath: logPath,
            skippedPublish: false,
            summary: "Published \(version) from \(effectiveSnapshot.sha.prefix(7))",
            releaseChannel: releaseChannel
        )
    }

    private func verifyPublishedAppcast(
        repository: RepositoryConfiguration,
        checkoutPath: String,
        releaseChannel: ReleaseChannel,
        expectedMarketingVersion: String,
        expectedBuildVersion: String
    ) throws {
        let docsDirectory = "\(checkoutPath)/docs"
        let appcastPath: String
        switch releaseChannel {
        case .stable:
            appcastPath = "\(docsDirectory)/appcast.xml"
        case .beta:
            appcastPath = "\(docsDirectory)/beta/appcast.xml"
        }

        guard FileManager.default.fileExists(atPath: appcastPath) else {
            throw NSError(
                domain: "ShipHook",
                code: 810,
                userInfo: [NSLocalizedDescriptionKey: "Publish command completed, but expected appcast was not written to \(appcastPath)."]
            )
        }

        let appcast = try String(contentsOfFile: appcastPath, encoding: .utf8)
        let expectedShortVersion = "<sparkle:shortVersionString>\(expectedMarketingVersion)</sparkle:shortVersionString>"
        guard appcast.contains(expectedShortVersion) else {
            throw NSError(
                domain: "ShipHook",
                code: 811,
                userInfo: [NSLocalizedDescriptionKey: "Publish command completed, but \(URL(fileURLWithPath: appcastPath).lastPathComponent) does not contain version \(expectedMarketingVersion)."]
            )
        }

        if !expectedBuildVersion.isEmpty {
            let expectedBuild = "<sparkle:version>\(expectedBuildVersion)</sparkle:version>"
            guard appcast.contains(expectedBuild) else {
                throw NSError(
                    domain: "ShipHook",
                    code: 812,
                    userInfo: [NSLocalizedDescriptionKey: "Publish command completed, but \(URL(fileURLWithPath: appcastPath).lastPathComponent) does not contain build \(expectedBuildVersion)."]
                )
            }
        }

        if let notifications = repository.notifications,
           (notifications.postOnSuccess || notifications.postOnFailure),
           let webhookURL = notifications.discordWebhookURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !webhookURL.isEmpty {
            _ = webhookURL
        }
    }

    private func syncRepository(
        _ repository: RepositoryConfiguration,
        checkoutPath: String,
        sha: String,
        onStageChange: ((PipelineStage) -> Void)?,
        onOutput: ((String) -> Void)?
    ) throws -> String {
        try cleanShipHookVersionMutationIfNeeded(repository, checkoutPath: checkoutPath, onOutput: onOutput)

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

        if currentHead != sha {
            onOutput?("Branch advanced during sync from \(String(sha.prefix(7))) to \(String(currentHead.prefix(7))); using the synchronized HEAD.\n")
        }

        return currentHead
    }

    private func resolvedSynchronizedSnapshot(
        for repository: RepositoryConfiguration,
        checkoutPath: String,
        fallback: GitHubBranchSnapshot,
        synchronizedSHA: String
    ) throws -> GitHubBranchSnapshot {
        guard synchronizedSHA != fallback.sha else {
            return fallback
        }

        let message = try commandRunner
            .run("git -C '\(checkoutPath)' log -1 --format=%B '\(synchronizedSHA)'", currentDirectory: checkoutPath, environment: [:])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let committedAtRaw = try commandRunner
            .run("git -C '\(checkoutPath)' log -1 --format=%cI '\(synchronizedSHA)'", currentDirectory: checkoutPath, environment: [:])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = ISO8601DateFormatter()
        let committedAt = formatter.date(from: committedAtRaw)
        let htmlURL = URL(string: "https://github.com/\(repository.owner)/\(repository.repo)/commit/\(synchronizedSHA)")

        return GitHubBranchSnapshot(
            sha: synchronizedSHA,
            committedAt: committedAt ?? fallback.committedAt,
            message: message.isEmpty ? fallback.message : message,
            htmlURL: htmlURL ?? fallback.htmlURL
        )
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

    private func cleanShipHookVersionMutationIfNeeded(
        _ repository: RepositoryConfiguration,
        checkoutPath: String,
        onOutput: ((String) -> Void)?
    ) throws {
        try cleanShipHookGeneratedDocsIfNeeded(checkoutPath: checkoutPath, onOutput: onOutput)

        guard repository.buildMode == .xcodeArchive, let xcode = repository.xcode else {
            return
        }

        let statusOutput = try commandRunner
            .run("git -C '\(checkoutPath)' status --porcelain", currentDirectory: checkoutPath, environment: [:])
            .output

        let changedPaths = statusOutput
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.count >= 4 else { return nil }
                return String(line.dropFirst(3))
            }

        guard changedPaths.count == 1,
              let changedPath = changedPaths.first,
              let projectPath = xcode.projectPath?.expandingTildeInPath else {
            return
        }

        let pbxprojPath = "\(projectPath)/project.pbxproj"
        let relativePBXProjPath = makeRelativePath(pbxprojPath, from: checkoutPath)
        guard changedPath == relativePBXProjPath else {
            return
        }

        let diffOutput = try commandRunner
            .run("git -C '\(checkoutPath)' diff -- '\(pbxprojPath)'", currentDirectory: checkoutPath, environment: [:])
            .output

        let onlyVersionSettingsChanged = diffOutput
            .split(separator: "\n")
            .allSatisfy { line in
                let text = String(line)
                guard text.hasPrefix("+") || text.hasPrefix("-") else {
                    return true
                }
                if text.hasPrefix("+++") || text.hasPrefix("---") {
                    return true
                }
                return text.contains("MARKETING_VERSION = ") || text.contains("CURRENT_PROJECT_VERSION = ")
            }

        guard onlyVersionSettingsChanged else {
            return
        }

        onOutput?("Restoring ShipHook-managed version bump before syncing repository.\n")
        _ = try commandRunner.run(
            "git -C '\(checkoutPath)' restore '\(pbxprojPath)'",
            currentDirectory: checkoutPath,
            environment: [:],
            onOutput: onOutput
        )
    }

    private func cleanShipHookGeneratedDocsIfNeeded(
        checkoutPath: String,
        onOutput: ((String) -> Void)?
    ) throws {
        let statusOutput = try commandRunner
            .run("git -C '\(checkoutPath)' status --porcelain", currentDirectory: checkoutPath, environment: [:])
            .output

        var trackedPathsToRestore: [String] = []
        var untrackedPathsToRemove: [String] = []

        for line in statusOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line)
            guard text.count >= 4 else { continue }
            let status = String(text.prefix(2))
            let path = String(text.dropFirst(3))

            guard isShipHookGeneratedDocsPath(path) else {
                continue
            }

            if status == "??" {
                untrackedPathsToRemove.append(path)
            } else {
                trackedPathsToRestore.append(path)
            }
        }

        if !trackedPathsToRestore.isEmpty {
            onOutput?("Restoring ShipHook-managed appcast documentation before syncing repository.\n")
            let quotedPaths = trackedPathsToRestore.map { "'\($0)'" }.joined(separator: " ")
            _ = try commandRunner.run(
                "git -C '\(checkoutPath)' restore -- \(quotedPaths)",
                currentDirectory: checkoutPath,
                environment: [:],
                onOutput: onOutput
            )
        }

        for path in untrackedPathsToRemove {
            let absolutePath = "\(checkoutPath)/\(path)"
            guard FileManager.default.fileExists(atPath: absolutePath) else {
                continue
            }
            onOutput?("Removing generated ShipHook file \(path) before syncing repository.\n")
            try FileManager.default.removeItem(atPath: absolutePath)
        }
    }

    private func isShipHookGeneratedDocsPath(_ relativePath: String) -> Bool {
        relativePath == "docs/appcast.xml"
            || relativePath == "docs/beta/appcast.xml"
            || relativePath.hasPrefix("docs/release-notes/")
            || relativePath.hasPrefix("docs/beta/release-notes/")
    }

    private func resolvedReleaseNotesSource(
        for repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot,
        checkoutPath: String
    ) throws -> ReleaseNotesSource {
        let snapshotTitle = snapshot.message
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Release"

        let isMergeCommit = (try? isMergeCommit(at: checkoutPath)) ?? false
        guard isMergeCommit else {
            return ReleaseNotesSource(
                sha: snapshot.sha,
                title: snapshotTitle,
                message: snapshot.message,
                commitURL: snapshot.htmlURL
            )
        }

        let fallback = try nearestNonMergeCommit(for: repository, in: checkoutPath)
        guard let fallback, !fallback.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ReleaseNotesSource(
                sha: snapshot.sha,
                title: snapshotTitle,
                message: snapshot.message,
                commitURL: snapshot.htmlURL
            )
        }

        return fallback
    }

    private func isMergeCommit(at checkoutPath: String) throws -> Bool {
        let parents = try commandRunner
            .run("git -C '\(checkoutPath)' show -s --format=%P HEAD", currentDirectory: checkoutPath, environment: [:])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        return parents.count > 1
    }

    private func nearestNonMergeCommit(
        for repository: RepositoryConfiguration,
        in checkoutPath: String
    ) throws -> ReleaseNotesSource? {
        let output = try commandRunner
            .run("git -C '\(checkoutPath)' log --no-merges -n 1 --format='%H%x1f%s%x1f%b' HEAD", currentDirectory: checkoutPath, environment: [:])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !output.isEmpty else {
            return nil
        }

        let fields = output.components(separatedBy: "\u{1f}")
        guard let sha = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sha.isEmpty else {
            return nil
        }

        let title = fields.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Release"
        let body = fields.dropFirst(2).joined(separator: "\u{1f}")
        let message = ([title] + [body.trimmingCharacters(in: .whitespacesAndNewlines)])
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let commitURL: URL?
        if !repository.owner.isEmpty, !repository.repo.isEmpty {
            commitURL = URL(string: "https://github.com/\(repository.owner)/\(repository.repo)/commit/\(sha)")
        } else {
            commitURL = nil
        }
        return ReleaseNotesSource(sha: sha, title: title, message: message, commitURL: commitURL)
    }

    private func resolvedReleaseNotesPath(
        for repository: RepositoryConfiguration,
        releaseNotesSource: ReleaseNotesSource,
        checkoutPath: String,
        version: String
    ) throws -> String {
        if let configuredPath = repository.releaseNotesPath?.expandingTildeInPath,
           !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configuredPath
        }

        let releaseNotesDirectory = "\(checkoutPath)/.shiphook/release-notes"
        let releaseNotesPath = "\(releaseNotesDirectory)/\(repository.id)-\(sanitizedFilenameComponent(version)).html"
        let title = releaseNotesSource.title.nilIfEmpty ?? "Release \(version)"

        let html = makeReleaseNotesHTML(
            title: title,
            version: version,
            message: releaseNotesSource.message,
            shortSHA: String(releaseNotesSource.sha.prefix(7)),
            commitURL: releaseNotesSource.commitURL
        )

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: releaseNotesDirectory),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try html.write(to: URL(fileURLWithPath: releaseNotesPath), atomically: true, encoding: .utf8)
        return releaseNotesPath
    }

    private func makeReleaseNotesHTML(
        title: String,
        version: String,
        message: String,
        shortSHA: String,
        commitURL: URL?
    ) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = trimmedMessage
            .components(separatedBy: CharacterSet.newlines)
            .split(whereSeparator: { $0.allSatisfy(\.isWhitespace) })
            .map { block in
                block
                    .map { line in line.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map(\.htmlEscaped)
                    .joined(separator: "<br>")
            }
            .filter { !$0.isEmpty }

        let bodyHTML = paragraphs.isEmpty
            ? "<p>No release notes were provided for this build.</p>"
            : paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")

        let commitLine: String
        if let commitURL {
            commitLine = #"<p><strong>Commit:</strong> <a href="\#(commitURL.absoluteString.htmlEscaped)">\#(shortSHA.htmlEscaped)</a></p>"#
        } else {
            commitLine = "<p><strong>Commit:</strong> \(shortSHA.htmlEscaped)</p>"
        }

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title.htmlEscaped) - Release Notes</title>
          <style>
            :root { color-scheme: light dark; }
            body {
              margin: 0;
              padding: 32px 20px 48px;
              font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: #f4f6f8;
              color: #0f1720;
            }
            main {
              max-width: 760px;
              margin: 0 auto;
              padding: 28px;
              border-radius: 22px;
              background: rgba(255, 255, 255, 0.86);
              box-shadow: 0 20px 60px rgba(15, 23, 32, 0.10);
            }
            h1 { margin: 0 0 6px; font-size: 30px; line-height: 1.15; }
            .meta { margin: 0 0 24px; color: #52606d; font-size: 14px; }
            p { margin: 0 0 16px; }
            a { color: #0a67a3; text-decoration: none; }
            a:hover { text-decoration: underline; }
            @media (prefers-color-scheme: dark) {
              body { background: #0b1015; color: #edf2f7; }
              main {
                background: rgba(15, 23, 32, 0.88);
                box-shadow: 0 24px 70px rgba(0, 0, 0, 0.45);
              }
              .meta { color: #9fb0c2; }
              a { color: #73c3ff; }
            }
          </style>
        </head>
        <body>
          <main>
            <h1>\(title.htmlEscaped)</h1>
            <p class="meta">Version \(version.htmlEscaped)</p>
            \(bodyHTML)
            \(commitLine)
          </main>
        </body>
        </html>
        """
    }

    private func sanitizedFilenameComponent(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = string.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "release" : sanitized
    }

    private func makeRelativePath(_ path: String, from root: String) -> String {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let pathURL = URL(fileURLWithPath: path)
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let pathComponents = pathURL.standardizedFileURL.pathComponents

        guard pathComponents.starts(with: rootComponents) else {
            return pathURL.path
        }

        return pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func postDiscordWebhookIfNeeded(
        repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot,
        version: String,
        releaseChannel: ReleaseChannel,
        appcastURL: String?,
        artifactPath: String,
        releaseNotesSource: ReleaseNotesSource,
        onOutput: ((String) -> Void)?
    ) {
        guard let notifications = repository.notifications,
              notifications.postOnSuccess,
              let webhookURL = notifications.discordWebhookURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !webhookURL.isEmpty else {
            return
        }

        guard let url = URL(string: webhookURL) else {
            onOutput?("Skipping Discord webhook: invalid URL.\n")
            return
        }

        let channelLabel = releaseChannel == .beta ? "beta" : "stable"
        let releaseNotesSummary = summarizedReleaseNotesText(from: releaseNotesSource.message)
        let fields: [[String: Any]] = [
            ["name": "Repository", "value": "\(repository.owner)/\(repository.repo)", "inline": true],
            ["name": "Commit", "value": String(snapshot.sha.prefix(7)), "inline": true],
            ["name": "Channel", "value": channelLabel.capitalized, "inline": true],
            ["name": "Artifact", "value": URL(fileURLWithPath: artifactPath).lastPathComponent, "inline": true],
            ["name": "Appcast", "value": appcastURL ?? "N/A", "inline": false],
            ["name": "Release Notes", "value": releaseNotesSummary, "inline": false],
        ]

        let payload: [String: Any] = [
            "content": "ShipHook published **\(repository.name)** \(version) on the **\(channelLabel)** channel.",
            "embeds": [[
                "title": "\(repository.name) \(version)",
                "description": releaseNotesSource.title,
                "url": releaseNotesSource.commitURL?.absoluteString ?? snapshot.htmlURL?.absoluteString ?? "",
                "color": releaseChannel == .beta ? 16_717_567 : 5_768_191,
                "fields": fields,
            ]]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            onOutput?("Skipping Discord webhook: could not encode payload.\n")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let semaphore = DispatchSemaphore(value: 0)
        var requestError: Error?
        var responseCode: Int?

        URLSession.shared.dataTask(with: request) { _, response, error in
            requestError = error
            responseCode = (response as? HTTPURLResponse)?.statusCode
            semaphore.signal()
        }.resume()

        semaphore.wait()

        if let requestError {
            onOutput?("Discord webhook failed: \(requestError.localizedDescription)\n")
            return
        }

        guard let responseCode, (200..<300).contains(responseCode) else {
            onOutput?("Discord webhook failed with HTTP \(responseCode ?? -1).\n")
            return
        }

        onOutput?("Posted Discord webhook notification.\n")
    }

    private func summarizedReleaseNotesText(from message: String) -> String {
        let collapsed = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else {
            return "No release notes were provided."
        }

        if collapsed.count <= 900 {
            return collapsed
        }

        let truncated = collapsed.prefix(897)
        return "\(truncated)..."
    }

    private func normalizeCodeSigningIfNeeded(
        artifactPath: String,
        repository: RepositoryConfiguration,
        checkoutPath: String,
        onOutput: ((String) -> Void)?
    ) throws {
        guard
            let signing = repository.signing,
            signing.codeSignStyle == .manual,
            let identity = signing.codeSignIdentity,
            !identity.isEmpty
        else {
            return
        }

        _ = try commandRunner.run(
            """
            /usr/bin/codesign --force --deep --sign '\(identity)' --timestamp --options runtime --preserve-metadata=identifier,entitlements,requirements,flags '\(artifactPath)'
            """,
            currentDirectory: checkoutPath,
            environment: [:],
            onOutput: onOutput
        )
    }

    private func notarizeAndStapleAppIfNeeded(
        artifactPath: String,
        repository: RepositoryConfiguration,
        checkoutPath: String,
        onStageChange: ((PipelineStage) -> Void)?,
        onOutput: ((String) -> Void)?
    ) throws {
        guard let profile = repository.signing?.notarizationProfile, !profile.isEmpty else {
            return
        }

        let fileManager = FileManager.default
        let notarizationDirectory = "\(checkoutPath)/.shiphook/notarization"
        let appName = URL(fileURLWithPath: artifactPath).deletingPathExtension().lastPathComponent
        let uploadPath = "\(notarizationDirectory)/\(appName)-notary.zip"

        try fileManager.createDirectory(
            at: URL(fileURLWithPath: notarizationDirectory),
            withIntermediateDirectories: true,
            attributes: nil
        )
        if fileManager.fileExists(atPath: uploadPath) {
            try fileManager.removeItem(atPath: uploadPath)
        }

        onStageChange?(.notarizing)
        _ = try commandRunner.run(
            "ditto -c -k --sequesterRsrc --keepParent '\(artifactPath)' '\(uploadPath)'",
            currentDirectory: checkoutPath,
            environment: [:],
            onOutput: onOutput
        )
        let submitResult = try commandRunner.run(
            "xcrun notarytool submit '\(uploadPath)' --keychain-profile '\(profile)' --wait --output-format json",
            currentDirectory: checkoutPath,
            environment: [:],
            onOutput: onOutput
        )
        try validateNotarizationSubmission(
            submitResult.output,
            profile: profile,
            checkoutPath: checkoutPath,
            onOutput: onOutput
        )
        _ = try commandRunner.run(
            "xcrun stapler staple '\(artifactPath)'",
            currentDirectory: checkoutPath,
            environment: [:],
            onOutput: onOutput
        )
        _ = try commandRunner.run(
            "xcrun stapler validate '\(artifactPath)'",
            currentDirectory: checkoutPath,
            environment: [:],
            onOutput: onOutput
        )
    }

    private func validateNotarizationSubmission(
        _ output: String,
        profile: String,
        checkoutPath: String,
        onOutput: ((String) -> Void)?
    ) throws {
        guard
            let data = output.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        let status = (json["status"] as? String) ?? ""
        if status.caseInsensitiveCompare("Accepted") == .orderedSame {
            return
        }

        let submissionID = (json["id"] as? String) ?? ""
        var message = "Apple notarization failed with status \(status.isEmpty ? "Unknown" : status)."

        if !submissionID.isEmpty {
            let logResult = try? commandRunner.run(
                "xcrun notarytool log '\(submissionID)' --keychain-profile '\(profile)' --output-format json",
                currentDirectory: checkoutPath,
                environment: [:],
                onOutput: onOutput
            )
            if let logOutput = logResult?.output,
               let logMessage = summarizeNotaryLog(logOutput),
               !logMessage.isEmpty {
                message += "\n\(logMessage)"
            } else {
                message += "\nSubmission ID: \(submissionID)"
            }
        }

        throw NotarizationError.invalidSubmission(message)
    }

    private func summarizeNotaryLog(_ output: String) -> String? {
        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var lines: [String] = []
        if let status = json["status"] as? String, !status.isEmpty {
            lines.append("Notary status: \(status)")
        }
        if let issues = json["issues"] as? [[String: Any]], !issues.isEmpty {
            for issue in issues.prefix(6) {
                let path = (issue["path"] as? String) ?? "unknown path"
                let message = (issue["message"] as? String) ?? "Unknown notarization issue"
                lines.append("\(path): \(message)")
            }
        }

        if lines.isEmpty {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines.joined(separator: "\n")
    }

    private func applyBetaIconIfNeeded(
        artifactPath: String,
        repository: RepositoryConfiguration,
        releaseChannel: ReleaseChannel,
        checkoutPath: String,
        onOutput: ((String) -> Void)?
    ) throws {
        guard releaseChannel == .beta else {
            return
        }
        guard
            let iconPath = repository.sparkle?.betaIconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !iconPath.isEmpty
        else {
            return
        }

        let sourcePath = iconPath.expandingTildeInPath
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw NSError(
                domain: "ShipHook",
                code: 830,
                userInfo: [NSLocalizedDescriptionKey: "Beta icon file does not exist at \(sourcePath)."]
            )
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard sourceURL.pathExtension.lowercased() == "icns" else {
            // Non-.icns beta icon overrides are handled before archive by replacing source icon files.
            return
        }

        let resourcesDirectory = URL(fileURLWithPath: artifactPath).appendingPathComponent("Contents/Resources", isDirectory: true)
        try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true, attributes: nil)
        let destinationURL = resourcesDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let infoPlistURL = URL(fileURLWithPath: artifactPath).appendingPathComponent("Contents/Info.plist")
        guard let infoPlist = NSMutableDictionary(contentsOf: infoPlistURL) else {
            throw NSError(
                domain: "ShipHook",
                code: 832,
                userInfo: [NSLocalizedDescriptionKey: "Could not load app Info.plist to apply beta icon at \(infoPlistURL.path)."]
            )
        }

        let iconBaseName = sourceURL.deletingPathExtension().lastPathComponent
        infoPlist["CFBundleIconFile"] = iconBaseName
        infoPlist["CFBundleIconName"] = iconBaseName
        guard infoPlist.write(to: infoPlistURL, atomically: true) else {
            throw NSError(
                domain: "ShipHook",
                code: 833,
                userInfo: [NSLocalizedDescriptionKey: "Could not update Info.plist with beta icon settings."]
            )
        }

        onOutput?("Applied beta icon \(sourceURL.lastPathComponent) to \(URL(fileURLWithPath: artifactPath).lastPathComponent).\n")
    }

    private func applyReleaseChannelMetadata(
        artifactPath: String,
        releaseChannel: ReleaseChannel,
        onOutput: ((String) -> Void)?
    ) throws {
        let infoPlistURL = URL(fileURLWithPath: artifactPath).appendingPathComponent("Contents/Info.plist")
        guard let infoPlist = NSMutableDictionary(contentsOf: infoPlistURL) else {
            throw NSError(
                domain: "ShipHook",
                code: 840,
                userInfo: [NSLocalizedDescriptionKey: "Could not load app Info.plist to apply release channel metadata at \(infoPlistURL.path)."]
            )
        }

        // Persist a single boolean marker for beta builds.
        if releaseChannel == .beta {
            infoPlist["ShipHookIsBetaBuild"] = true
        } else {
            infoPlist.removeObject(forKey: "ShipHookIsBetaBuild")
        }

        guard infoPlist.write(to: infoPlistURL, atomically: true) else {
            throw NSError(
                domain: "ShipHook",
                code: 841,
                userInfo: [NSLocalizedDescriptionKey: "Could not update Info.plist with release channel metadata."]
            )
        }

        onOutput?("Embedded release channel metadata in app Info.plist (\(releaseChannel.rawValue)).\n")
    }

    private func prepareBetaSourceIconOverrideIfNeeded(
        repository: RepositoryConfiguration,
        releaseChannel: ReleaseChannel,
        checkoutPath: String,
        onOutput: ((String) -> Void)?
    ) throws -> (() throws -> Void)? {
        guard releaseChannel == .beta else {
            return nil
        }
        guard repository.buildMode == .xcodeArchive, let xcode = repository.xcode else {
            return nil
        }
        guard
            let configuredPath = repository.sparkle?.betaIconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !configuredPath.isEmpty
        else {
            return nil
        }

        let sourcePath = configuredPath.expandingTildeInPath
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw NSError(
                domain: "ShipHook",
                code: 834,
                userInfo: [NSLocalizedDescriptionKey: "Configured beta icon file does not exist at \(sourcePath)."]
            )
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard sourceExtension == "icon" else {
            return nil
        }

        let destinationPath = try resolveSourceIconPath(
            repository: repository,
            xcode: xcode,
            checkoutPath: checkoutPath,
            expectedExtension: sourceExtension
        )
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let backupURL = destinationURL.appendingPathExtension("shiphook-backup")
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        if destinationExists {
            try fileManager.copyItem(at: destinationURL, to: backupURL)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        onOutput?("Applied beta source icon override \(sourceURL.lastPathComponent) -> \(destinationURL.lastPathComponent) before archive.\n")

        return {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            if destinationExists, fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.moveItem(at: backupURL, to: destinationURL)
                onOutput?("Restored source icon \(destinationURL.lastPathComponent) after beta build.\n")
            } else if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
        }
    }

    private func resolveSourceIconPath(
        repository: RepositoryConfiguration,
        xcode: XcodeBuildConfiguration,
        checkoutPath: String,
        expectedExtension: String
    ) throws -> String {
        let settings = try fetchBuildSettings(xcode: xcode, checkoutPath: checkoutPath)
        let sourceRoot = (settings["SRCROOT"] ?? checkoutPath).expandingTildeInPath
        let appIconName = settings["ASSETCATALOG_COMPILER_APPICON_NAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let appIconName, !appIconName.isEmpty,
           let namedMatch = findFirstMatchingFile(
               under: sourceRoot,
               fileName: "\(appIconName).\(expectedExtension)",
               excluding: repository.sparkle?.betaIconPath?.expandingTildeInPath
           ) {
            return namedMatch
        }

        if let genericMatch = findFirstFile(
            under: sourceRoot,
            withExtension: expectedExtension,
            excluding: repository.sparkle?.betaIconPath?.expandingTildeInPath
        ) {
            return genericMatch
        }

        throw NSError(
            domain: "ShipHook",
            code: 835,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate a source .\(expectedExtension) icon to override in \(sourceRoot)."]
        )
    }

    private func fetchBuildSettings(xcode: XcodeBuildConfiguration, checkoutPath: String) throws -> [String: String] {
        let targetFlag: String
        let commandDirectory: String
        if let workspacePath = xcode.sanitizedWorkspacePath?.expandingTildeInPath, !workspacePath.isEmpty {
            targetFlag = "-workspace '\(workspacePath)'"
            commandDirectory = URL(fileURLWithPath: workspacePath).deletingLastPathComponent().path
        } else if let projectPath = xcode.projectPath?.expandingTildeInPath, !projectPath.isEmpty {
            targetFlag = "-project '\(projectPath)'"
            commandDirectory = URL(fileURLWithPath: projectPath).deletingLastPathComponent().path
        } else {
            throw NSError(
                domain: "ShipHook",
                code: 836,
                userInfo: [NSLocalizedDescriptionKey: "Cannot inspect build settings without project or workspace path."]
            )
        }

        let command = "xcodebuild \(targetFlag) -scheme '\(xcode.scheme)' -configuration '\(xcode.configuration)' -showBuildSettings -json"
        let output = try commandRunner.run(command, currentDirectory: commandDirectory, environment: [:]).output
        let data = try extractJSONData(from: output)
        let decoded = try JSONDecoder().decode([PipelineBuildSettingsResponse].self, from: data)
        return decoded.first?.buildSettings ?? [:]
    }

    private func extractJSONData(from output: String) throws -> Data {
        if let data = output.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        for marker in ["[", "{"] {
            for index in output.indices where output[index] == Character(marker) {
                let slice = output[index...]
                guard let data = String(slice).data(using: .utf8),
                      (try? JSONSerialization.jsonObject(with: data)) != nil else {
                    continue
                }
                return data
            }
        }

        throw CocoaError(.coderReadCorrupt)
    }

    private func findFirstMatchingFile(under root: String, fileName: String, excluding excludedPath: String?) -> String? {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else {
            return nil
        }

        let normalizedExcluded = excludedPath?.expandingTildeInPath
        for case let relativePath as String in enumerator {
            let absolutePath = "\(root)/\(relativePath)"
            if let normalizedExcluded, absolutePath == normalizedExcluded {
                continue
            }
            if URL(fileURLWithPath: absolutePath).lastPathComponent == fileName {
                return absolutePath
            }
        }
        return nil
    }

    private func findFirstFile(under root: String, withExtension pathExtension: String, excluding excludedPath: String?) -> String? {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else {
            return nil
        }

        let normalizedExcluded = excludedPath?.expandingTildeInPath
        for case let relativePath as String in enumerator {
            let absolutePath = "\(root)/\(relativePath)"
            if let normalizedExcluded, absolutePath == normalizedExcluded {
                continue
            }
            if URL(fileURLWithPath: absolutePath).pathExtension.lowercased() == pathExtension {
                return absolutePath
            }
        }
        return nil
    }

    private func resolvedReleaseChannel(requestedChannel: ReleaseChannel, version: AppVersion) -> ReleaseChannel {
        if requestedChannel == .beta {
            return .beta
        }

        if hasBetaVersionMarker(version.marketingVersion) || hasBetaVersionMarker(version.buildVersion) {
            return .beta
        }

        return .stable
    }

    private func hasBetaVersionMarker(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return false
        }

        if trimmed.contains("beta") || trimmed.contains("pre") || trimmed.contains("rc") {
            return true
        }

        return trimmed.hasPrefix("b")
    }

    private func requestedReleaseChannel(snapshotMessage: String, releaseNotesMessage: String) -> ReleaseChannel {
        if releaseChannel(for: snapshotMessage) == .beta || releaseChannel(for: releaseNotesMessage) == .beta {
            return .beta
        }
        return .stable
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

private struct PipelineBuildSettingsResponse: Decodable {
    var buildSettings: [String: String]
}

private extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }

    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private func releaseChannel(for snapshot: GitHubBranchSnapshot) -> ReleaseChannel {
    releaseChannel(for: snapshot.message)
}

private func releaseChannel(for message: String) -> ReleaseChannel {
    let lowercasedMessage = message.lowercased()
    let betaMarkers = ["[beta]", "[shiphook beta]", "[pre-release]", "[prerelease]"]
    return betaMarkers.contains(where: { lowercasedMessage.contains($0) }) ? .beta : .stable
}
