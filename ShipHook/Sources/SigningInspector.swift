import Foundation

struct SigningIdentity: Hashable, Identifiable {
    enum Kind: String {
        case developerIDApplication = "Developer ID Application"
        case developerIDInstaller = "Developer ID Installer"
        case appleDevelopment = "Apple Development"
        case appleDistribution = "Apple Distribution"
        case macDeveloper = "Mac Developer"
        case unknown = "Other"
    }

    let fingerprint: String
    let commonName: String
    let teamID: String?
    let kind: Kind

    var id: String { fingerprint }

    var displayName: String {
        if let teamID {
            return "\(commonName) [\(teamID)]"
        }
        return commonName
    }

    var isRecommendedForSparkle: Bool {
        kind == .developerIDApplication
    }
}

struct SigningInspectionResult {
    let identities: [SigningIdentity]
    let recommendedIdentity: SigningIdentity?
}

struct SigningDiagnostics {
    let summary: String
    let details: [String]
}

enum SigningPreflightError: LocalizedError {
    case noValidIdentities
    case manualIdentityMissing(String)
    case unsupportedManualIdentity(String)

    var errorDescription: String? {
        switch self {
        case .noValidIdentities:
            return "No valid code-signing identities were found on this Mac. If Keychain Access shows a certificate but not its private key, Xcode still cannot sign with it."
        case let .manualIdentityMissing(identity):
            return "The configured signing identity was not found as a valid local codesigning identity: \(identity)"
        case let .unsupportedManualIdentity(identity):
            return "Sparkle release archives should use a Developer ID Application identity, not \(identity)."
        }
    }
}

final class SigningInspector {
    private let shell = ShellCommandRunner()

    func inspectAvailableIdentities() throws -> SigningInspectionResult {
        let result = try shell.run(
            "security find-identity -v -p codesigning",
            currentDirectory: "/",
            environment: [:]
        )

        let identities = result.output
            .split(separator: "\n")
            .compactMap { parseIdentityLine(String($0)) }

        return SigningInspectionResult(
            identities: identities,
            recommendedIdentity: identities.first(where: \.isRecommendedForSparkle) ?? identities.first
        )
    }

    func diagnostics() throws -> SigningDiagnostics {
        let inspection = try inspectAvailableIdentities()
        let developerIDIdentities = inspection.identities.filter { $0.kind == .developerIDApplication }
        let developmentIdentities = inspection.identities.filter { $0.kind == .appleDevelopment || $0.kind == .macDeveloper }

        var details: [String] = []
        details.append("Valid local codesigning identities: \(inspection.identities.count)")

        if developerIDIdentities.isEmpty {
            details.append("Developer ID Application identities: none")
        } else {
            details.append("Developer ID Application identities: \(developerIDIdentities.map(\.displayName).joined(separator: ", "))")
        }

        if developmentIdentities.isEmpty {
            details.append("Development identities: none")
        } else {
            details.append("Development identities: \(developmentIdentities.map(\.displayName).joined(separator: ", "))")
        }

        let summary: String
        if inspection.identities.isEmpty {
            summary = "No valid codesigning identities are available to command-line tools on this Mac."
            details.append("If Keychain Access shows a certificate but `security find-identity` does not, the private key is usually missing or inaccessible.")
        } else if developerIDIdentities.isEmpty {
            summary = "Command-line signing works, but there is no valid Developer ID Application identity for Sparkle release archives."
            details.append("ShipHook can build development archives with development certs, but Sparkle release distribution should use Developer ID Application plus notarization.")
        } else {
            summary = "This Mac has a valid Developer ID Application identity for Sparkle release archives."
        }

        return SigningDiagnostics(summary: summary, details: details)
    }

    func validateReleaseSigning(_ signing: SigningConfiguration?) throws {
        let inspection = try inspectAvailableIdentities()

        guard !inspection.identities.isEmpty else {
            throw SigningPreflightError.noValidIdentities
        }

        guard let signing else {
            return
        }

        if signing.codeSignStyle == .manual {
            guard let identityName = signing.codeSignIdentity, !identityName.isEmpty else {
                throw SigningPreflightError.manualIdentityMissing("No identity configured")
            }

            guard let identity = inspection.identities.first(where: { $0.commonName == identityName }) else {
                throw SigningPreflightError.manualIdentityMissing(identityName)
            }

            guard identity.kind == .developerIDApplication else {
                throw SigningPreflightError.unsupportedManualIdentity(identityName)
            }
        }
    }

    private func parseIdentityLine(_ line: String) -> SigningIdentity? {
        let pattern = #"^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(.+)"$"#
        guard let match = line.captureGroups(matching: pattern), match.count == 2 else {
            return nil
        }

        let fingerprint = match[0]
        let commonName = match[1]
        let teamID = commonName.lastTeamIdentifier
        let kind = SigningIdentity.Kind(commonName: commonName)
        return SigningIdentity(
            fingerprint: fingerprint,
            commonName: commonName,
            teamID: teamID,
            kind: kind
        )
    }
}

private extension SigningIdentity.Kind {
    init(commonName: String) {
        if commonName.hasPrefix("Developer ID Application:") {
            self = .developerIDApplication
        } else if commonName.hasPrefix("Developer ID Installer:") {
            self = .developerIDInstaller
        } else if commonName.hasPrefix("Apple Development:") {
            self = .appleDevelopment
        } else if commonName.hasPrefix("Apple Distribution:") {
            self = .appleDistribution
        } else if commonName.hasPrefix("Mac Developer:") {
            self = .macDeveloper
        } else {
            self = .unknown
        }
    }
}

private extension String {
    var lastTeamIdentifier: String? {
        guard let match = captureGroups(matching: #"\(([A-Z0-9]{10})\)\s*$"#), let teamID = match.first else {
            return nil
        }
        return teamID
    }

    func captureGroups(matching pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range), match.numberOfRanges > 1 else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: self) else {
                return nil
            }
            return String(self[swiftRange])
        }
    }
}
