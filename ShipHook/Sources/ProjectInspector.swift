import Foundation

struct ProjectInspectionResult {
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
    private let commandRunner = ShellCommandRunner()

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
        let remote = try? commandRunner.run("git -C '\(root)' remote get-url origin", currentDirectory: root, environment: [:]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = try? commandRunner.run("git -C '\(root)' rev-parse --abbrev-ref HEAD", currentDirectory: root, environment: [:]).output.trimmingCharacters(in: .whitespacesAndNewlines)

        let parsedRemote = remote.flatMap(parseGitHubRemote(_:))
        let suggestedScheme = schemes.first
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
        let command: String
        if let workspacePath, !workspacePath.isEmpty {
            command = "xcodebuild -workspace '\(workspacePath)' -list -json"
        } else if let projectPath, !projectPath.isEmpty {
            command = "xcodebuild -project '\(projectPath)' -list -json"
        } else {
            return []
        }

        let output = try commandRunner.run(command, currentDirectory: root, environment: [:]).output
        let data = try extractJSON(from: output)
        let decoded = try JSONDecoder().decode(XcodeListResponse.self, from: data)
        return decoded.schemes
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
            if next.contains("/.build/") || next.contains("/Pods/") || next.hasPrefix(".git/") {
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
            if next.contains("/.build/") || next.contains("/Pods/") || next.hasPrefix(".git/") {
                continue
            }
            if (next as NSString).pathExtension == pathExtension {
                return "\(root)/\(next)"
            }
        }
        return nil
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
