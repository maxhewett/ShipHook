import Foundation

struct AppVersion: Equatable {
    var marketingVersion: String
    var buildVersion: String
}

struct AppcastVersion: Equatable {
    var marketingVersion: String?
    var buildVersion: String
}

struct ReleasePlan {
    var version: AppVersion
    var appcastURL: String?
    var latestAppcastItem: AppcastVersion?
    var appliedBuildMutation: Bool
    var originalVersion: AppVersion
}

struct ReleaseInspection {
    var projectVersion: AppVersion
    var latestAppcastItem: AppcastVersion?
    var appcastURL: String?
    var suggestedNextBuild: String
}

enum ReleasePlannerError: LocalizedError {
    case xcodeProjectRequired
    case nonNumericBuild(String)
    case missingVersionSettings
    case couldNotUpdateProjectVersion

    var errorDescription: String? {
        switch self {
        case .xcodeProjectRequired:
            return "A concrete .xcodeproj path is required to update build/version settings."
        case let .nonNumericBuild(build):
            return "Sparkle requires a numeric build version. Found: \(build)"
        case .missingVersionSettings:
            return "Could not determine MARKETING_VERSION or CURRENT_PROJECT_VERSION from the target project."
        case .couldNotUpdateProjectVersion:
            return "ShipHook could not update the target project's MARKETING_VERSION/CURRENT_PROJECT_VERSION."
        }
    }
}

struct ReleasePlanner {
    private let commandRunner = ShellCommandRunner()

    func prepareRelease(for repository: RepositoryConfiguration) throws -> ReleasePlan? {
        guard repository.buildMode == .xcodeArchive, let xcode = repository.xcode else {
            return nil
        }

        let current = try inspectProjectVersion(xcode: xcode)
        let latest = try fetchLatestAppcastVersion(for: repository)
        let desiredBuild = try computeNextBuild(currentBuild: current.buildVersion, latestAppcast: latest, autoIncrement: repository.sparkle?.autoIncrementBuild ?? true)

        var mutated = false
        if desiredBuild != current.buildVersion {
            try updateProjectVersion(xcode: xcode, marketingVersion: current.marketingVersion, buildVersion: desiredBuild)
            mutated = true
        }

        return ReleasePlan(
            version: AppVersion(marketingVersion: current.marketingVersion, buildVersion: desiredBuild),
            appcastURL: resolvedAppcastURL(for: repository),
            latestAppcastItem: latest,
            appliedBuildMutation: mutated,
            originalVersion: current
        )
    }

    func inspectReleaseState(for repository: RepositoryConfiguration) throws -> ReleaseInspection? {
        guard repository.buildMode == .xcodeArchive, let xcode = repository.xcode else {
            return nil
        }

        let current = try inspectProjectVersion(xcode: xcode)
        let latest = try fetchLatestAppcastVersion(for: repository)
        let suggestedBuild = try computeNextBuild(currentBuild: current.buildVersion, latestAppcast: latest, autoIncrement: true)
        return ReleaseInspection(
            projectVersion: current,
            latestAppcastItem: latest,
            appcastURL: resolvedAppcastURL(for: repository),
            suggestedNextBuild: suggestedBuild
        )
    }

    func inspectProjectVersion(xcode: XcodeBuildConfiguration) throws -> AppVersion {
        let workingDirectory = ((xcode.sanitizedWorkspacePath ?? xcode.projectPath ?? "") as NSString).expandingTildeInPath
        let root = URL(fileURLWithPath: workingDirectory).deletingLastPathComponent().path
        let targetFlag: String
        if let workspacePath = xcode.sanitizedWorkspacePath, !workspacePath.isEmpty {
            targetFlag = "-workspace '\((workspacePath as NSString).expandingTildeInPath)'"
        } else if let projectPath = xcode.projectPath, !projectPath.isEmpty {
            targetFlag = "-project '\((projectPath as NSString).expandingTildeInPath)'"
        } else {
            throw ReleasePlannerError.xcodeProjectRequired
        }

        let command = "xcodebuild \(targetFlag) -scheme '\(xcode.scheme)' -configuration '\(xcode.configuration)' -showBuildSettings -json"
        let output = try commandRunner.run(command, currentDirectory: root, environment: [:]).output
        let data = try JSONExtraction.extract(from: output)
        let response = try JSONDecoder().decode([BuildSettingsResponse].self, from: data)
        guard let settings = response.first?.buildSettings else {
            throw ReleasePlannerError.missingVersionSettings
        }

        let marketingVersion = settings["MARKETING_VERSION"] ?? settings["CFBundleShortVersionString"]
        let buildVersion = settings["CURRENT_PROJECT_VERSION"] ?? settings["CFBundleVersion"]

        guard let marketingVersion, let buildVersion else {
            throw ReleasePlannerError.missingVersionSettings
        }

        return AppVersion(marketingVersion: marketingVersion, buildVersion: buildVersion)
    }

    private func fetchLatestAppcastVersion(for repository: RepositoryConfiguration) throws -> AppcastVersion? {
        guard let urlString = resolvedAppcastURL(for: repository), let url = URL(string: urlString) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let parser = AppcastParser()
        return parser.parse(data: data)
    }

    private func computeNextBuild(currentBuild: String, latestAppcast: AppcastVersion?, autoIncrement: Bool) throws -> String {
        guard let current = Int(currentBuild) else {
            throw ReleasePlannerError.nonNumericBuild(currentBuild)
        }

        guard let latest = latestAppcast else {
            return currentBuild
        }

        guard let latestBuild = Int(latest.buildVersion) else {
            throw ReleasePlannerError.nonNumericBuild(latest.buildVersion)
        }

        if current > latestBuild {
            return currentBuild
        }

        if autoIncrement {
            return String(latestBuild + 1)
        }

        throw ReleasePlannerError.nonNumericBuild("Current build \(currentBuild) is not newer than appcast build \(latest.buildVersion)")
    }

    private func updateProjectVersion(xcode: XcodeBuildConfiguration, marketingVersion: String, buildVersion: String) throws {
        guard let projectPath = xcode.projectPath, !projectPath.isEmpty else {
            throw ReleasePlannerError.xcodeProjectRequired
        }

        let pbxprojPath = "\((projectPath as NSString).expandingTildeInPath)/project.pbxproj"
        let command = """
        perl -0pi -e 's/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = \(marketingVersion);/g; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = \(buildVersion);/g' '\(pbxprojPath)'
        """
        _ = try commandRunner.run(command, currentDirectory: URL(fileURLWithPath: pbxprojPath).deletingLastPathComponent().path, environment: [:])
    }

    func restoreProjectVersionIfNeeded(_ plan: ReleasePlan?, xcode: XcodeBuildConfiguration?) throws {
        guard let plan, plan.appliedBuildMutation, let xcode else {
            return
        }

        try updateProjectVersion(
            xcode: xcode,
            marketingVersion: plan.originalVersion.marketingVersion,
            buildVersion: plan.originalVersion.buildVersion
        )
    }

    private func resolvedAppcastURL(for repository: RepositoryConfiguration) -> String? {
        if let explicit = repository.sparkle?.appcastURL, !explicit.isEmpty {
            return explicit
        }

        guard !repository.owner.isEmpty, !repository.repo.isEmpty else {
            return nil
        }

        return "https://\(repository.owner).github.io/\(repository.repo)/appcast.xml"
    }
}

private enum JSONExtraction {
    static func extract(from output: String) throws -> Data {
        if let data = output.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
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
}

private struct BuildSettingsResponse: Decodable {
    var buildSettings: [String: String]
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentTitle = ""
    private var currentBuildVersion = ""
    private var currentShortVersion = ""
    private var currentElementText = ""
    private var latestItem: AppcastVersion?

    func parse(data: Data) -> AppcastVersion? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return latestItem
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = qName ?? elementName
        currentElementText = ""
        if elementName == "item" {
            currentTitle = ""
            currentBuildVersion = attributeDict["sparkle:version"] ?? ""
            currentShortVersion = attributeDict["sparkle:shortVersionString"] ?? ""
        }
        if elementName == "enclosure" {
            if currentBuildVersion.isEmpty {
                currentBuildVersion = attributeDict["sparkle:version"] ?? ""
            }
            if currentShortVersion.isEmpty {
                currentShortVersion = attributeDict["sparkle:shortVersionString"] ?? ""
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentElementText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let resolvedElement = qName ?? elementName
        let trimmedText = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch resolvedElement {
        case "title":
            currentTitle += trimmedText
        case "sparkle:version":
            if !trimmedText.isEmpty {
                currentBuildVersion = trimmedText
            }
        case "sparkle:shortVersionString":
            if !trimmedText.isEmpty {
                currentShortVersion = trimmedText
            }
        default:
            break
        }

        if elementName == "item", latestItem == nil, !currentBuildVersion.isEmpty {
            latestItem = AppcastVersion(
                marketingVersion: currentShortVersion.isEmpty ? currentTitle.trimmingCharacters(in: .whitespacesAndNewlines) : currentShortVersion,
                buildVersion: currentBuildVersion
            )
        }
        currentElement = ""
        currentElementText = ""
    }
}
