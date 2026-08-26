import AppKit
import Foundation

struct ProjectInspectionResult: Codable {
    var owner: String?
    var repo: String?
    var branch: String?
    var workspacePath: String?
    var projectPath: String?
    var schemes: [String]
    var suggestedScheme: String?
    var releaseNotesPath: String?
}

enum ProjectInspectorError: LocalizedError {
    case pathNotFound
    case noXcodeProject

    var errorDescription: String? {
        switch self {
        case .pathNotFound:
            return "The local checkout path does not exist."
        case .noXcodeProject:
            return "No .xcodeproj or .xcworkspace was found in the checkout."
        }
    }
}

struct ProjectInspector {
    private let fileManager = FileManager.default
    private let processRunner = ProcessCommandRunner()

    func inspect(localCheckoutPath: String) throws -> ProjectInspectionResult {
        let root = (localCheckoutPath as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectInspectorError.pathNotFound
        }

        let workspacePath = findFirstWorkspacePath(under: root)
        let projectPath = findFirstPath(withExtension: "xcodeproj", under: root)
        guard workspacePath != nil || projectPath != nil else {
            throw ProjectInspectorError.noXcodeProject
        }

        let schemes = try findSchemes(workspacePath: workspacePath, projectPath: projectPath, root: root)
        let remote = try? processRunner.run("git", arguments: ["remote", "get-url", "origin"], currentDirectory: root).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = try? processRunner.run("git", arguments: ["rev-parse", "--abbrev-ref", "HEAD"], currentDirectory: root).output.trimmingCharacters(in: .whitespacesAndNewlines)

        let parsedRemote = remote.flatMap(parseGitHubRemote(_:))
        let suggestedScheme = suggestScheme(
            from: schemes,
            workspacePath: workspacePath,
            projectPath: projectPath,
            root: root
        )
        let releaseNotesPath = findReleaseNotesPath(under: root)

        return ProjectInspectionResult(
            owner: parsedRemote?.owner,
            repo: parsedRemote?.repo,
            branch: branch,
            workspacePath: workspacePath,
            projectPath: projectPath,
            schemes: schemes,
            suggestedScheme: suggestedScheme,
            releaseNotesPath: releaseNotesPath
        )
    }

    private func findSchemes(workspacePath: String?, projectPath: String?, root: String) throws -> [String] {
        var commands: [[String]] = []
        if let workspacePath, !workspacePath.isEmpty {
            commands.append(["-workspace", workspacePath, "-list", "-json"])
        }
        if let projectPath, !projectPath.isEmpty {
            commands.append(["-project", projectPath, "-list", "-json"])
        }
        guard !commands.isEmpty else {
            return []
        }

        var lastError: Error?
        for arguments in commands {
            do {
                let output = try processRunner.run("xcodebuild", arguments: arguments, currentDirectory: root).output
                let data = try extractJSON(from: output)
                let decoded = try JSONDecoder().decode(XcodeListResponse.self, from: data)
                if !decoded.schemes.isEmpty {
                    return decoded.schemes
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }

    private func suggestScheme(
        from schemes: [String],
        workspacePath: String?,
        projectPath: String?,
        root: String
    ) -> String? {
        guard !schemes.isEmpty else {
            return nil
        }

        let preferredNames = Set([
            rootName(for: root),
            rootName(for: workspacePath),
            rootName(for: projectPath),
        ].compactMap(normalizeName(_:)))

        let metadataByName = sharedSchemeMetadata(
            workspacePath: workspacePath,
            projectPath: projectPath
        )

        return schemes.max { lhs, rhs in
            score(for: lhs, preferredNames: preferredNames, metadata: metadataByName[lhs])
                < score(for: rhs, preferredNames: preferredNames, metadata: metadataByName[rhs])
        }
    }

    private func sharedSchemeMetadata(
        workspacePath: String?,
        projectPath: String?
    ) -> [String: SchemeMetadata] {
        let candidateDirectories = [
            workspacePath.map { "\($0)/xcshareddata/xcschemes" },
            projectPath.map { "\($0)/xcshareddata/xcschemes" },
        ].compactMap { $0 }

        var metadata: [String: SchemeMetadata] = [:]
        for directory in candidateDirectories {
            guard let enumerator = fileManager.enumerator(atPath: directory) else {
                continue
            }

            while let next = enumerator.nextObject() as? String {
                guard (next as NSString).pathExtension == "xcscheme" else {
                    continue
                }

                let fullPath = (directory as NSString).appendingPathComponent(next)
                let schemeName = ((next as NSString).lastPathComponent as NSString).deletingPathExtension
                guard metadata[schemeName] == nil else {
                    continue
                }

                metadata[schemeName] = parseSchemeMetadata(at: fullPath)
            }
        }

        return metadata
    }

    private func parseSchemeMetadata(at path: String) -> SchemeMetadata {
        guard let data = fileManager.contents(atPath: path),
              let parser = XMLParser(data: data) as XMLParser? else {
            return .empty
        }

        let delegate = SchemeMetadataParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.metadata
    }

    private func score(
        for scheme: String,
        preferredNames: Set<String>,
        metadata: SchemeMetadata?
    ) -> Int {
        let normalizedScheme = normalizeName(scheme) ?? ""
        let normalizedBlueprint = normalizeName(metadata?.primaryBlueprintName)
        let normalizedBuildable = normalizeName(metadata?.primaryBuildableName)

        var score = 0
        if preferredNames.contains(normalizedScheme) {
            score += 100
        }
        if let normalizedBlueprint, preferredNames.contains(normalizedBlueprint) {
            score += 90
        }
        if let normalizedBuildable, preferredNames.contains(normalizedBuildable) {
            score += 80
        }
        if metadata?.buildableNameHasAppSuffix == true {
            score += 40
        }
        if normalizedScheme.hasSuffix("tests") {
            score -= 50
        }
        if normalizedScheme.hasSuffix("cli") {
            score -= 15
        }
        return score
    }

    private func rootName(for path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func normalizeName(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let withoutExtension = (trimmed as NSString).deletingPathExtension
        let stripped = withoutExtension.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        guard !stripped.isEmpty else {
            return nil
        }
        return String(String.UnicodeScalarView(stripped)).lowercased()
    }

    private func findReleaseNotesPath(under root: String) -> String? {
        let candidates = [
            "\(root)/docs/release-notes/latest.html",
            "\(root)/docs/release-notes/index.html",
        ]
        return candidates.first(where: fileManager.fileExists(atPath:))
    }

    private func findFirstWorkspacePath(under root: String) -> String? {
        let enumerator = fileManager.enumerator(atPath: root)
        while let next = enumerator?.nextObject() as? String {
            if shouldSkipInspectionPath(next) {
                continue
            }
            if next.contains(".xcodeproj/") {
                continue
            }
            if (next as NSString).pathExtension == "xcworkspace" {
                return "\(root)/\(next)"
            }
        }
        return nil
    }

    private func findFirstPath(withExtension pathExtension: String, under root: String) -> String? {
        let enumerator = fileManager.enumerator(atPath: root)
        while let next = enumerator?.nextObject() as? String {
            if shouldSkipInspectionPath(next) {
                continue
            }
            if (next as NSString).pathExtension == pathExtension {
                return "\(root)/\(next)"
            }
        }
        return nil
    }

    private func shouldSkipInspectionPath(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/")
        return components.contains(".git")
            || components.contains(".build")
            || components.contains("Pods")
            || components.contains(".swiftpm")
            || components.contains("DerivedData")
    }

    private func parseGitHubRemote(_ remote: String) -> (owner: String, repo: String)? {
        let patterns = [
            #"github\.com[:/]([^/]+)/([^/.]+)(\.git)?$"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: remote, range: NSRange(remote.startIndex..., in: remote)),
               let ownerRange = Range(match.range(at: 1), in: remote),
               let repoRange = Range(match.range(at: 2), in: remote) {
                return (String(remote[ownerRange]), String(remote[repoRange]))
            }
        }
        return nil
    }

    private func extractJSON(from output: String) throws -> Data {
        if let data = output.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        for marker in ["{", "["] {
            for index in output.indices where output[index] == Character(marker) {
                let candidate = String(output[index...])
                guard let data = candidate.data(using: .utf8),
                      (try? JSONSerialization.jsonObject(with: data)) != nil else {
                    continue
                }
                return data
            }
        }

        throw CocoaError(.coderReadCorrupt)
    }
}

private struct SchemeMetadata {
    var primaryBlueprintName: String?
    var primaryBuildableName: String?

    static let empty = SchemeMetadata(primaryBlueprintName: nil, primaryBuildableName: nil)

    var buildableNameHasAppSuffix: Bool {
        primaryBuildableName?.hasSuffix(".app") == true
    }
}

private final class SchemeMetadataParser: NSObject, XMLParserDelegate {
    private(set) var metadata = SchemeMetadata.empty
    private var hasCapturedPrimaryBuildActionEntry = false
    private var isInsidePrimaryBuildActionEntry = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !hasCapturedPrimaryBuildActionEntry else {
            return
        }

        if elementName == "BuildActionEntry" {
            isInsidePrimaryBuildActionEntry = true
            return
        }

        guard elementName == "BuildableReference", isInsidePrimaryBuildActionEntry else {
            return
        }

        metadata.primaryBlueprintName = attributeDict["BlueprintName"]
        metadata.primaryBuildableName = attributeDict["BuildableName"]
        hasCapturedPrimaryBuildActionEntry = true
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "BuildActionEntry" {
            isInsidePrimaryBuildActionEntry = false
        }
    }
}

private struct XcodeListResponse: Decodable {
    struct Container: Decodable {
        var schemes: [String]?
    }

    var project: Container?
    var workspace: Container?

    var schemes: [String] {
        project?.schemes ?? workspace?.schemes ?? []
    }
}

struct RepositoryIconResolver {
    private let fileManager = FileManager.default

    func resolveIcon(for repository: RepositoryConfiguration) -> NSImage {
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

        if let image = NSImage(named: NSImage.applicationIconName) {
            return image
        }

        return NSImage(size: NSSize(width: 64, height: 64))
    }

}
