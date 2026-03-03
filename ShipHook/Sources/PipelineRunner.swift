import Foundation

struct PipelineOutcome {
    var builtSHA: String
    var version: String
    var artifactPath: String
    var log: String
    var logPath: String
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
        let releaseNotesPath = try resolvedReleaseNotesPath(
            for: repository,
            snapshot: snapshot,
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
            "SHIPHOOK_SHA": snapshot.sha,
            "SHIPHOOK_SHORT_SHA": String(snapshot.sha.prefix(7)),
            "SHIPHOOK_VERSION": version,
            "SHIPHOOK_BUILD_VERSION": buildVersion,
            "SHIPHOOK_LOCAL_CHECKOUT_PATH": checkoutPath,
            "SHIPHOOK_RELEASE_NOTES_PATH": releaseNotesPath,
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

    private func resolvedReleaseNotesPath(
        for repository: RepositoryConfiguration,
        snapshot: GitHubBranchSnapshot,
        checkoutPath: String,
        version: String
    ) throws -> String {
        if let configuredPath = repository.releaseNotesPath?.expandingTildeInPath,
           !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configuredPath
        }

        let releaseNotesDirectory = "\(checkoutPath)/.shiphook/release-notes"
        let releaseNotesPath = "\(releaseNotesDirectory)/\(repository.id)-\(sanitizedFilenameComponent(version)).html"
        let title = snapshot.message
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Release \(version)"

        let html = makeReleaseNotesHTML(
            title: title,
            version: version,
            message: snapshot.message,
            shortSHA: String(snapshot.sha.prefix(7)),
            commitURL: snapshot.htmlURL
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
