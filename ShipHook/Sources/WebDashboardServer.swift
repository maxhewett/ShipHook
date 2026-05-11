import CryptoKit
import Foundation
import Security
import Swifter

struct WebDashboardSnapshot: Codable {
    var generatedAt: Date
    var global: Global
    var repositories: [Repository]

    struct Global: Codable {
        var pollIntervalSeconds: Double
        var githubToken: String?
        var githubTokenEnvVar: String?
        var generatedDataRetentionCount: Int
        var autoPauseFailureCount: Int
        var webDashboardEnabled: Bool
        var webDashboardPort: Int
        var configPath: String
        var hasUnsavedChanges: Bool
        var lastGlobalError: String?
        var launchesAtLogin: Bool
        var launchAtLoginStatusMessage: String?
        var webDashboardStatusMessage: String
        var webDashboardURLString: String?
        var availableNotarizationProfiles: [String]
        var lastSigningIdentityError: String?
        var signingDiagnosticsSummary: String?
        var signingDiagnosticsDetails: [String]
        var availableSigningIdentities: [SigningIdentityOption]

        static let empty = Global(
            pollIntervalSeconds: 300,
            githubToken: nil,
            githubTokenEnvVar: "GITHUB_TOKEN",
            generatedDataRetentionCount: 3,
            autoPauseFailureCount: 3,
            webDashboardEnabled: false,
            webDashboardPort: 8787,
            configPath: "",
            hasUnsavedChanges: false,
            lastGlobalError: nil,
            launchesAtLogin: false,
            launchAtLoginStatusMessage: nil,
            webDashboardStatusMessage: "Local web dashboard is turned off.",
            webDashboardURLString: nil,
            availableNotarizationProfiles: [],
            lastSigningIdentityError: nil,
            signingDiagnosticsSummary: nil,
            signingDiagnosticsDetails: [],
            availableSigningIdentities: []
        )
    }

    struct SigningIdentityOption: Codable {
        var fingerprint: String
        var commonName: String
        var teamID: String?
        var kind: String
        var displayName: String
        var isRecommendedForSparkle: Bool
    }

    struct Repository: Codable {
        var id: String
        var name: String
        var iconDataURL: String?
        var configuration: RepositoryConfiguration
        var runtime: Runtime
        var version: String?
        var publishedVersion: String?
        var latestBuild: Build?
        var recentBuilds: [Build]
        var recentReleases: [Release]
        var progress: Progress?

        struct Runtime: Codable {
            var isEnabled: Bool
            var slug: String
            var branch: String
            var activity: String
            var phase: String
            var summary: String
            var releaseChannel: String?
            var version: String?
            var publishedVersion: String?
            var lastSeenSHA: String?
            var lastBuiltSHA: String?
            var lastCheckDate: Date?
            var lastSuccessDate: Date?
            var buildStartedAt: Date?
            var lastCommitAuthorLogin: String?
            var lastCommitAuthorAvatarURL: String?
            var lastCommitAuthorProfileURL: String?
            var lastLog: String
            var lastLogPath: String?
        }
    }

    struct Build: Codable {
        var version: String
        var sha: String
        var builtAt: Date
        var releaseChannel: String?
        var authorLogin: String?
        var authorAvatarURL: String?
        var authorProfileURL: String?
        var summary: String?
        var logPath: String?
    }

    struct Release: Codable {
        var tagName: String
        var name: String
        var body: String
        var isPrerelease: Bool
        var publishedAt: Date?
        var htmlURL: String?
        var authorLogin: String?
        var authorAvatarURL: String?
        var authorProfileURL: String?
    }

    struct Progress: Codable {
        var currentStep: Int
        var totalSteps: Int
        var label: String
        var fractionComplete: Double
    }
}

struct WebDashboardNotarizationProfileInput: Codable {
    var profileName: String
    var appleID: String
    var teamID: String
    var appSpecificPassword: String
}

struct WebDashboardRepositoryInspectionRequest: Codable {
    var localCheckoutPath: String
    var fallbackOwner: String
    var fallbackRepo: String
    var fallbackBranch: String
}

struct WebDashboardRepositoryInspectionPreview: Codable {
    var inspection: ProjectInspectionResult
    var suggestedRepository: RepositoryConfiguration
}

struct WebDashboardRepositoryInspectionSubmission: Codable {
    var localCheckoutPath: String
    var fallbackOwner: String
    var fallbackRepo: String
    var fallbackBranch: String
    var selectedScheme: String?
}

enum WebDashboardCommand: Codable {
    case saveConfiguration(AppConfiguration)
    case reloadConfiguration
    case addRepository
    case inspectRepository(WebDashboardRepositoryInspectionRequest)
    case addRepositoryFromInspection(WebDashboardRepositoryInspectionSubmission)
    case removeRepository(String)
    case pollAll
    case pollRepository(String)
    case recloneRepository(String)
    case setRepositoryEnabled(repositoryID: String, enabled: Bool)
    case resetBuildState(String)
    case refreshReleases(String)
    case rollbackRelease(repositoryID: String, tagName: String)
    case setLaunchAtLogin(Bool)
    case refreshSigningIdentities
    case storeNotarizationProfile(WebDashboardNotarizationProfileInput)

    private enum CodingKeys: String, CodingKey {
        case type
        case configuration
        case inspectionRequest
        case inspectionSubmission
        case repositoryID
        case tagName
        case enabled
        case notarizationProfile
    }

    private enum CommandType: String, Codable {
        case saveConfiguration
        case reloadConfiguration
        case addRepository
        case inspectRepository
        case addRepositoryFromInspection
        case removeRepository
        case pollAll
        case pollRepository
        case recloneRepository
        case setRepositoryEnabled
        case resetBuildState
        case refreshReleases
        case rollbackRelease
        case setLaunchAtLogin
        case refreshSigningIdentities
        case storeNotarizationProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)

        switch type {
        case .saveConfiguration:
            self = .saveConfiguration(try container.decode(AppConfiguration.self, forKey: .configuration))
        case .reloadConfiguration:
            self = .reloadConfiguration
        case .addRepository:
            self = .addRepository
        case .inspectRepository:
            self = .inspectRepository(try container.decode(WebDashboardRepositoryInspectionRequest.self, forKey: .inspectionRequest))
        case .addRepositoryFromInspection:
            self = .addRepositoryFromInspection(try container.decode(WebDashboardRepositoryInspectionSubmission.self, forKey: .inspectionSubmission))
        case .removeRepository:
            self = .removeRepository(try container.decode(String.self, forKey: .repositoryID))
        case .pollAll:
            self = .pollAll
        case .pollRepository:
            self = .pollRepository(try container.decode(String.self, forKey: .repositoryID))
        case .recloneRepository:
            self = .recloneRepository(try container.decode(String.self, forKey: .repositoryID))
        case .setRepositoryEnabled:
            self = .setRepositoryEnabled(
                repositoryID: try container.decode(String.self, forKey: .repositoryID),
                enabled: try container.decode(Bool.self, forKey: .enabled)
            )
        case .resetBuildState:
            self = .resetBuildState(try container.decode(String.self, forKey: .repositoryID))
        case .refreshReleases:
            self = .refreshReleases(try container.decode(String.self, forKey: .repositoryID))
        case .rollbackRelease:
            self = .rollbackRelease(
                repositoryID: try container.decode(String.self, forKey: .repositoryID),
                tagName: try container.decode(String.self, forKey: .tagName)
            )
        case .setLaunchAtLogin:
            self = .setLaunchAtLogin(try container.decode(Bool.self, forKey: .enabled))
        case .refreshSigningIdentities:
            self = .refreshSigningIdentities
        case .storeNotarizationProfile:
            self = .storeNotarizationProfile(
                try container.decode(WebDashboardNotarizationProfileInput.self, forKey: .notarizationProfile)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .saveConfiguration(configuration):
            try container.encode(CommandType.saveConfiguration, forKey: .type)
            try container.encode(configuration, forKey: .configuration)
        case .reloadConfiguration:
            try container.encode(CommandType.reloadConfiguration, forKey: .type)
        case .addRepository:
            try container.encode(CommandType.addRepository, forKey: .type)
        case let .inspectRepository(request):
            try container.encode(CommandType.inspectRepository, forKey: .type)
            try container.encode(request, forKey: .inspectionRequest)
        case let .addRepositoryFromInspection(submission):
            try container.encode(CommandType.addRepositoryFromInspection, forKey: .type)
            try container.encode(submission, forKey: .inspectionSubmission)
        case let .removeRepository(repositoryID):
            try container.encode(CommandType.removeRepository, forKey: .type)
            try container.encode(repositoryID, forKey: .repositoryID)
        case .pollAll:
            try container.encode(CommandType.pollAll, forKey: .type)
        case let .pollRepository(repositoryID):
            try container.encode(CommandType.pollRepository, forKey: .type)
            try container.encode(repositoryID, forKey: .repositoryID)
        case let .recloneRepository(repositoryID):
            try container.encode(CommandType.recloneRepository, forKey: .type)
            try container.encode(repositoryID, forKey: .repositoryID)
        case let .setRepositoryEnabled(repositoryID, enabled):
            try container.encode(CommandType.setRepositoryEnabled, forKey: .type)
            try container.encode(repositoryID, forKey: .repositoryID)
            try container.encode(enabled, forKey: .enabled)
        case let .resetBuildState(repositoryID):
            try container.encode(CommandType.resetBuildState, forKey: .type)
            try container.encode(repositoryID, forKey: .repositoryID)
        case let .refreshReleases(repositoryID):
            try container.encode(CommandType.refreshReleases, forKey: .type)
            try container.encode(repositoryID, forKey: .repositoryID)
        case let .rollbackRelease(repositoryID, tagName):
            try container.encode(CommandType.rollbackRelease, forKey: .type)
            try container.encode(repositoryID, forKey: .repositoryID)
            try container.encode(tagName, forKey: .tagName)
        case let .setLaunchAtLogin(enabled):
            try container.encode(CommandType.setLaunchAtLogin, forKey: .type)
            try container.encode(enabled, forKey: .enabled)
        case .refreshSigningIdentities:
            try container.encode(CommandType.refreshSigningIdentities, forKey: .type)
        case let .storeNotarizationProfile(profile):
            try container.encode(CommandType.storeNotarizationProfile, forKey: .type)
            try container.encode(profile, forKey: .notarizationProfile)
        }
    }
}

struct WebDashboardCommandResponse: Codable {
    var ok: Bool
    var message: String?
    var error: String?
    var snapshot: WebDashboardSnapshot
    var inspectionPreview: WebDashboardRepositoryInspectionPreview?
}

private struct WebDashboardErrorResponse: Encodable {
    var ok: Bool
    var error: String
}

private struct WebDashboardSecurityStateResponse: Codable {
    struct Admin: Codable {
        var username: String
        var mustChangePassword: Bool
        var createdAt: Date
        var isCurrentUser: Bool
    }

    struct Passkey: Codable {
        var username: String
        var name: String
        var addedAt: Date
    }

    struct AuditEntry: Codable {
        var id: String
        var occurredAt: Date
        var username: String?
        var action: String
        var detail: String?
        var remoteAddress: String?
    }

    var ok: Bool
    var currentUsername: String
    var admins: [Admin]
    var passkeys: [Passkey]
    var auditEntries: [AuditEntry]
}

final class WebDashboardServer {
    enum Status: Equatable {
        case stopped
        case running(url: String)
        case failed(message: String)

        var message: String {
            switch self {
            case .stopped:
                return "Local web dashboard is turned off."
            case let .running(url):
                return "Local web dashboard is available at \(url)"
            case let .failed(message):
                return message
            }
        }

        var urlString: String? {
            switch self {
            case let .running(url):
                return url
            case .stopped, .failed:
                return nil
            }
        }
    }

    private let snapshotProvider: @MainActor () -> WebDashboardSnapshot
    private let commandHandler: @MainActor (WebDashboardCommand) -> WebDashboardCommandResponse
    private let server = HttpServer()
    private let securityController = WebDashboardSecurityController()
    private var isConfigured = false
    private var currentPort: in_port_t?
    private var status: Status = .stopped

    init(
        snapshotProvider: @escaping @MainActor () -> WebDashboardSnapshot,
        commandHandler: @escaping @MainActor (WebDashboardCommand) -> WebDashboardCommandResponse
    ) {
        self.snapshotProvider = snapshotProvider
        self.commandHandler = commandHandler
    }

    func configure(enabled: Bool, port: Int) -> Status {
        stop()

        guard enabled else {
            status = .stopped
            return status
        }

        guard (1024...65535).contains(port) else {
            status = .failed(message: "Web dashboard port must be between 1024 and 65535.")
            return status
        }

        configureRoutesIfNeeded()

        let resolvedPort = in_port_t(clamping: port)
        do {
            try server.start(resolvedPort, forceIPv4: true)
            currentPort = resolvedPort
            status = .running(url: "http://localhost:\(resolvedPort)")
        } catch {
            currentPort = nil
            status = .failed(message: "Web dashboard failed to start: \(error.localizedDescription)")
        }

        return status
    }

    func currentStatus() -> Status {
        status
    }

    func stop() {
        server.stop()
        currentPort = nil
    }

    private func configureRoutesIfNeeded() {
        guard !isConfigured else {
            return
        }
        isConfigured = true

        server["/robots.txt"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.textResponse(
                "User-agent: *\nDisallow: /\n",
                statusCode: 200,
                reason: "OK",
                request: request,
                contentType: "text/plain; charset=utf-8"
            )
        }

        server.POST["/api/auth/setup"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleAuthSetup(request: request)
        }

        server.POST["/api/auth/login"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handlePasswordLogin(request: request)
        }

        server.POST["/api/auth/logout"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleLogout(request: request)
        }

        server["/api/auth/security-state"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleSecurityState(request: request)
        }

        server.POST["/api/auth/change-password"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handlePasswordChange(request: request)
        }

        server.POST["/api/auth/invite/accept"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleInviteAcceptance(request: request)
        }

        server.POST["/api/auth/admins/invite"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleAdminInvite(request: request)
        }

        server.POST["/api/auth/admins/reset"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleAdminReset(request: request)
        }

        server.POST["/api/auth/admins/delete"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleAdminDelete(request: request)
        }

        server.POST["/api/auth/passkeys/register/begin"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleBeginPasskeyRegistration(request: request)
        }

        server.POST["/api/auth/passkeys/register/finish"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleFinishPasskeyRegistration(request: request)
        }

        server.POST["/api/auth/passkeys/authenticate/begin"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleBeginPasskeyAuthentication(request: request)
        }

        server.POST["/api/auth/passkeys/authenticate/finish"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.handleFinishPasskeyAuthentication(request: request)
        }

        server["/api/state"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            guard self.securityController.isAuthorized(request: request) else {
                return self.unauthorizedJSONResponse(request: request)
            }
            return self.jsonResponse(for: self.currentSnapshot(), request: request)
        }

        server.POST["/api/command"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            guard self.securityController.isAuthorized(request: request) else {
                return self.unauthorizedJSONResponse(request: request)
            }
            do {
                let command = try self.decodeCommand(from: request)
                let response = self.perform(command)
                if response.ok {
                    let (action, detail) = self.auditDescription(for: command)
                    self.securityController.recordAuditEvent(
                        action: action,
                        detail: detail,
                        request: request,
                        username: self.securityController.currentUsername(request: request)
                    )
                }
                return self.jsonResponse(for: response, request: request)
            } catch {
                return self.errorResponse(message: error.localizedDescription, request: request)
            }
        }

        server["/security"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.securityPageResponse(for: request)
        }

        server["/"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.rootResponse(for: request)
        }

        server["/assets/glyph-dark.png"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.bundleImageResponse(named: "shiphoookglyphwhite", ext: "png", request: request)
        }

        server["/assets/glyph-light.png"] = { [weak self] request in
            guard let self else {
                return .internalServerError
            }
            return self.bundleImageResponse(named: "shiphoookglyphblack", ext: "png", request: request)
        }
    }

    private func currentSnapshot() -> WebDashboardSnapshot {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                snapshotProvider()
            }
        }
    }

    private func perform(_ command: WebDashboardCommand) -> WebDashboardCommandResponse {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                commandHandler(command)
            }
        }
    }

    private func decodeCommand(from request: HttpRequest) throws -> WebDashboardCommand {
        let data = Data(request.body)
        return try JSONDecoder.webDashboard.decode(WebDashboardCommand.self, from: data)
    }

    private func jsonResponse<T: Encodable>(for value: T, request: HttpRequest) -> HttpResponse {
        let encoder = JSONEncoder.webDashboard
        do {
            let data = try encoder.encode(value)
            return rawResponse(
                statusCode: 200,
                reason: "OK",
                body: data,
                contentType: "application/json; charset=utf-8",
                request: request
            )
        } catch {
            return .internalServerError
        }
    }

    private func errorResponse(message: String, request: HttpRequest) -> HttpResponse {
        let payload = WebDashboardErrorResponse(ok: false, error: message)
        return jsonResponse(for: payload, request: request)
    }

    private func unauthorizedJSONResponse(request: HttpRequest) -> HttpResponse {
        let payload = WebDashboardErrorResponse(ok: false, error: "Authentication required.")
        let encoder = JSONEncoder.webDashboard
        guard let data = try? encoder.encode(payload) else {
            return .unauthorized
        }
        return rawResponse(
            statusCode: 401,
            reason: "Unauthorized",
            body: data,
            contentType: "application/json; charset=utf-8",
            request: request
        )
    }

    private func htmlDocument() -> String {
        Self.htmlTemplate
    }

    private func rootResponse(for request: HttpRequest) -> HttpResponse {
        if securityController.isAuthorized(request: request) {
            if securityController.requiresPasswordChange(request: request) {
                return redirectResponse(to: "/security?force-password=1", request: request)
            }
            return htmlResponse(htmlDocument(), request: request)
        }

        if securityController.requiresBootstrap {
            if securityController.isBootstrapRequestAllowed(request: request) {
                return htmlResponse(securityController.setupPageHTML(), request: request)
            }
            return htmlResponse(
                securityController.bootstrapLockedPageHTML(),
                statusCode: 403,
                reason: "Forbidden",
                request: request
            )
        }

        let inviteToken = request.queryParams.first(where: { $0.0 == "invite" })?.1
        if let inviteToken,
           let inviteUsername = securityController.usernameForPasswordSetupToken(inviteToken) {
            return htmlResponse(
                securityController.inviteAcceptancePageHTML(username: inviteUsername, token: inviteToken),
                request: request
            )
        }
        return htmlResponse(
            securityController.loginPageHTML(passkeysAvailable: securityController.hasRegisteredPasskeys),
            request: request
        )
    }

    private func securityPageResponse(for request: HttpRequest) -> HttpResponse {
        guard securityController.isAuthorized(request: request) else {
            return redirectResponse(to: "/", request: request)
        }
        let forcePassword = request.queryParams.contains { $0.0 == "force-password" && $0.1 == "1" }
        return htmlResponse(securityController.securityPageHTML(forcePassword: forcePassword, currentUsername: securityController.currentUsername(request: request) ?? ""), request: request)
    }

    private func handleAuthSetup(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodeAuthSetupRequest(from: request)
            let result = try securityController.completeBootstrap(using: payload, request: request)
            if isURLEncodedForm(request) {
                return redirectResponse(to: "/", request: request)
            }
            return jsonResponse(for: result, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handlePasswordLogin(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodePasswordLoginRequest(from: request)
            let result = try securityController.login(using: payload, request: request)
            if isURLEncodedForm(request) {
                return redirectResponse(to: result.requiresPasswordChange == true ? "/security?force-password=1" : "/", request: request)
            }
            return jsonResponse(for: result, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleLogout(request: HttpRequest) -> HttpResponse {
        securityController.logout(request: request)
        return jsonResponse(for: WebDashboardAuthMessageResponse(ok: true, message: "Signed out."), request: request)
    }

    private func handleSecurityState(request: HttpRequest) -> HttpResponse {
        do {
            let response = try securityController.securityState(request: request)
            return jsonResponse(for: response, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handlePasswordChange(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodePasswordChangeRequest(from: request)
            try securityController.changePassword(using: payload, request: request)
            if isURLEncodedForm(request) {
                return redirectResponse(to: "/security", request: request)
            }
            return jsonResponse(for: WebDashboardAuthMessageResponse(ok: true, message: "Password updated."), request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleInviteAcceptance(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodeInviteAcceptanceRequest(from: request)
            let result = try securityController.acceptInvite(using: payload, request: request)
            if isURLEncodedForm(request) {
                return redirectResponse(to: "/", request: request)
            }
            return jsonResponse(for: result, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleAdminInvite(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodeRequest(WebDashboardAdminInviteRequest.self, from: request)
            let response = try securityController.inviteAdmin(username: payload.username, request: request)
            return jsonResponse(for: response, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleAdminReset(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodeRequest(WebDashboardAdminResetRequest.self, from: request)
            let response = try securityController.createPasswordResetLink(for: payload.username, request: request)
            return jsonResponse(for: response, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleAdminDelete(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodeRequest(WebDashboardAdminDeleteRequest.self, from: request)
            try securityController.deleteAdmin(username: payload.username, request: request)
            return jsonResponse(for: WebDashboardAuthMessageResponse(ok: true, message: "Administrator removed."), request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleBeginPasskeyRegistration(request: HttpRequest) -> HttpResponse {
        do {
            let response = try securityController.beginPasskeyRegistration(request: request)
            return jsonResponse(for: response, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleFinishPasskeyRegistration(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodeRequest(WebDashboardFinishPasskeyRegistrationRequest.self, from: request)
            let response = try securityController.finishPasskeyRegistration(using: payload, request: request)
            return jsonResponse(for: response, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleBeginPasskeyAuthentication(request: HttpRequest) -> HttpResponse {
        do {
            let response = try securityController.beginPasskeyAuthentication(request: request)
            return jsonResponse(for: response, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func handleFinishPasskeyAuthentication(request: HttpRequest) -> HttpResponse {
        do {
            let payload = try decodeRequest(WebDashboardFinishPasskeyAuthenticationRequest.self, from: request)
            let response = try securityController.finishPasskeyAuthentication(using: payload, request: request)
            return jsonResponse(for: response, request: request)
        } catch let error as WebDashboardSecurityController.SecurityError {
            return authErrorResponse(error, request: request)
        } catch {
            return errorResponse(message: error.localizedDescription, request: request)
        }
    }

    private func authErrorResponse(_ error: WebDashboardSecurityController.SecurityError, request: HttpRequest) -> HttpResponse {
        let response = WebDashboardAuthMessageResponse(ok: false, message: nil, error: error.userMessage, passkeysAvailable: securityController.hasRegisteredPasskeys)
        let encoder = JSONEncoder.webDashboard
        guard let data = try? encoder.encode(response) else {
            return .internalServerError
        }
        return rawResponse(
            statusCode: error.statusCode,
            reason: error.reasonPhrase,
            body: data,
            contentType: "application/json; charset=utf-8",
            request: request
        )
    }

    private func auditDescription(for command: WebDashboardCommand) -> (String, String?) {
        switch command {
        case .saveConfiguration:
            return ("dashboard.configuration.saved", nil)
        case .reloadConfiguration:
            return ("dashboard.configuration.reloaded", nil)
        case .addRepository:
            return ("dashboard.repository.blank_added", nil)
        case let .inspectRepository(request):
            return ("dashboard.repository.inspected", request.localCheckoutPath)
        case let .addRepositoryFromInspection(submission):
            return ("dashboard.repository.added_from_inspection", submission.localCheckoutPath)
        case let .removeRepository(repositoryID):
            return ("dashboard.repository.removed", repositoryID)
        case .pollAll:
            return ("dashboard.poll.all", nil)
        case let .pollRepository(repositoryID):
            return ("dashboard.poll.repository", repositoryID)
        case let .recloneRepository(repositoryID):
            return ("dashboard.repository.recloned", repositoryID)
        case let .setRepositoryEnabled(repositoryID, enabled):
            return (enabled ? "dashboard.repository.resumed" : "dashboard.repository.paused", repositoryID)
        case let .resetBuildState(repositoryID):
            return ("dashboard.build_state.reset", repositoryID)
        case let .refreshReleases(repositoryID):
            return ("dashboard.releases.refreshed", repositoryID)
        case let .rollbackRelease(repositoryID, tagName):
            return ("dashboard.release.rollback", "\(repositoryID) -> \(tagName)")
        case let .setLaunchAtLogin(enabled):
            return ("dashboard.launch_at_login.\(enabled ? "enabled" : "disabled")", nil)
        case .refreshSigningIdentities:
            return ("dashboard.signing_identities.refreshed", nil)
        case let .storeNotarizationProfile(profile):
            return ("dashboard.notarization_profile.stored", profile.profileName)
        }
    }

    private func decodeRequest<T: Decodable>(_ type: T.Type, from request: HttpRequest) throws -> T {
        try JSONDecoder.webDashboard.decode(T.self, from: Data(request.body))
    }

    private func decodeAuthSetupRequest(from request: HttpRequest) throws -> WebDashboardAuthSetupRequest {
        if isURLEncodedForm(request) {
            let form = Dictionary(uniqueKeysWithValues: request.parseUrlencodedForm())
            return WebDashboardAuthSetupRequest(
                username: form["username"] ?? "",
                password: form["password"] ?? "",
                publicBaseURL: emptyToNil(form["publicBaseURL"]),
                sessionDurationHours: Int(form["sessionDurationHours"] ?? "")
            )
        }
        return try decodeRequest(WebDashboardAuthSetupRequest.self, from: request)
    }

    private func decodePasswordLoginRequest(from request: HttpRequest) throws -> WebDashboardPasswordLoginRequest {
        if isURLEncodedForm(request) {
            let form = Dictionary(uniqueKeysWithValues: request.parseUrlencodedForm())
            return WebDashboardPasswordLoginRequest(
                username: form["username"] ?? "",
                password: form["password"] ?? ""
            )
        }
        return try decodeRequest(WebDashboardPasswordLoginRequest.self, from: request)
    }

    private func decodePasswordChangeRequest(from request: HttpRequest) throws -> WebDashboardPasswordChangeRequest {
        if isURLEncodedForm(request) {
            let form = Dictionary(uniqueKeysWithValues: request.parseUrlencodedForm())
            return WebDashboardPasswordChangeRequest(
                currentPassword: form["currentPassword"] ?? "",
                newPassword: form["newPassword"] ?? ""
            )
        }
        return try decodeRequest(WebDashboardPasswordChangeRequest.self, from: request)
    }

    private func decodeInviteAcceptanceRequest(from request: HttpRequest) throws -> WebDashboardInviteAcceptanceRequest {
        if isURLEncodedForm(request) {
            let form = Dictionary(uniqueKeysWithValues: request.parseUrlencodedForm())
            return WebDashboardInviteAcceptanceRequest(
                token: form["token"] ?? "",
                newPassword: form["newPassword"] ?? ""
            )
        }
        return try decodeRequest(WebDashboardInviteAcceptanceRequest.self, from: request)
    }

    private func isURLEncodedForm(_ request: HttpRequest) -> Bool {
        request.headers["content-type"]?.lowercased().contains("application/x-www-form-urlencoded") == true
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func htmlResponse(
        _ html: String,
        statusCode: Int = 200,
        reason: String = "OK",
        request: HttpRequest
    ) -> HttpResponse {
        rawResponse(
            statusCode: statusCode,
            reason: reason,
            body: Data(html.utf8),
            contentType: "text/html; charset=utf-8",
            request: request
        )
    }

    private func textResponse(
        _ text: String,
        statusCode: Int,
        reason: String,
        request: HttpRequest,
        contentType: String
    ) -> HttpResponse {
        rawResponse(
            statusCode: statusCode,
            reason: reason,
            body: Data(text.utf8),
            contentType: contentType,
            request: request
        )
    }

    private func redirectResponse(to location: String, request: HttpRequest) -> HttpResponse {
        var headers = securityHeaders(for: request)
        headers["Location"] = location
        return .raw(303, "See Other", headers, nil)
    }

    private func rawResponse(
        statusCode: Int,
        reason: String,
        body: Data,
        contentType: String,
        request: HttpRequest
    ) -> HttpResponse {
        var headers = securityHeaders(for: request)
        headers["Content-Type"] = contentType
        headers["Content-Length"] = "\(body.count)"
        if let cookie = securityController.pendingCookieHeader(for: request) {
            headers["Set-Cookie"] = cookie
        }
        return .raw(statusCode, reason, headers, { writer in
            try writer.write(body)
        })
    }

    private func securityHeaders(for request: HttpRequest) -> [String: String] {
        [
            "X-Robots-Tag": "noindex, nofollow, noarchive",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "Cross-Origin-Resource-Policy": "same-origin",
            "Cross-Origin-Opener-Policy": "same-origin",
            "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=(), publickey-credentials-get=(self), publickey-credentials-create=(self)",
            "Cache-Control": "no-store",
            "Content-Security-Policy": "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; font-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'"
        ]
    }

    private func bundleImageResponse(named name: String, ext: String, request: HttpRequest) -> HttpResponse {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url) else {
            return .notFound
        }
        return rawResponse(
            statusCode: 200,
            reason: "OK",
            body: data,
            contentType: "image/png",
            request: request
        )
    }

    private static let htmlTemplate = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ShipHook Control Room</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #101218;
      --bg-2: #171a22;
      --panel: rgba(19, 23, 31, 0.92);
      --panel-2: rgba(25, 31, 42, 0.92);
      --panel-3: rgba(14, 18, 26, 0.96);
      --line: rgba(255,255,255,0.08);
      --line-strong: rgba(255,255,255,0.18);
      --text: #f3efe6;
      --muted: #a7adbb;
      --accent: #ff875b;
      --accent-2: #4db8ff;
      --accent-3: #ffe082;
      --success: #52d49f;
      --warning: #ffbe55;
      --danger: #ff6d7a;
      --shadow: 0 20px 60px rgba(0, 0, 0, 0.34);
      --radius: 22px;
      --radius-sm: 16px;
      --font-body: "Avenir Next", "Segoe UI", sans-serif;
      --font-display: "Iowan Old Style", "Palatino Linotype", serif;
      --font-mono: ui-monospace, "SFMono-Regular", "SF Mono", Menlo, monospace;
    }
    @media (prefers-color-scheme: light) {
      :root {
        --bg: #eef3f8;
        --bg-2: #f7fafc;
        --panel: rgba(255, 255, 255, 0.88);
        --panel-2: rgba(252, 253, 255, 0.94);
        --panel-3: rgba(244, 248, 252, 0.95);
        --line: rgba(33, 49, 76, 0.10);
        --line-strong: rgba(33, 49, 76, 0.20);
        --text: #182233;
        --muted: #66758b;
        --accent: #d86a38;
        --accent-2: #227bbd;
        --accent-3: #936b10;
        --success: #1f9f6e;
        --warning: #b97b12;
        --danger: #d14e5c;
        --shadow: 0 18px 46px rgba(72, 95, 130, 0.14);
      }
      body {
        background:
          radial-gradient(circle at top left, rgba(216,106,56,0.14), transparent 28%),
          radial-gradient(circle at 88% 10%, rgba(34,123,189,0.12), transparent 26%),
          linear-gradient(180deg, #f7fafc 0%, #edf3f8 44%, #e7eef5 100%);
      }
      .summary-pill,
      .badge,
      .button,
      .toggle,
      input[type="text"],
      input[type="number"],
      input[type="password"],
      textarea,
      select,
      .summary-row,
      .item,
      .log-panel,
      .topnav,
      .toast,
      .modal-card,
      .repo-subhead-icon,
      .avatar {
        border-color: rgba(33, 49, 76, 0.10);
      }
      .summary-pill,
      .badge {
        background: rgba(24, 34, 51, 0.04);
        color: var(--text);
      }
      .summary-pill .muted,
      .repo-meta,
      .muted,
      .tiny,
      .panel h2,
      .editor-section h3,
      label.field,
      .summary-row-label {
        color: var(--muted);
      }
      .stack,
      .repo-card,
      .panel,
      .editor-section,
      .card,
      .summary-row,
      .item,
      .modal-card {
        background: rgba(255,255,255,0.78);
      }
      .hero {
        background:
          linear-gradient(135deg, rgba(216,106,56,0.12), rgba(34,123,189,0.05) 52%, rgba(147,107,16,0.06)),
          rgba(255,255,255,0.90);
      }
      .hero::after {
        background: linear-gradient(90deg, rgba(216,106,56,0), rgba(216,106,56,0.16), rgba(34,123,189,0));
      }
      .repo-card {
        background:
          linear-gradient(180deg, rgba(24,34,51,0.02), rgba(24,34,51,0)),
          rgba(255,255,255,0.82);
      }
      .repo-card.active {
        background:
          linear-gradient(180deg, rgba(216,106,56,0.12), rgba(216,106,56,0.03)),
          rgba(255,250,247,0.96);
      }
      .repo-icon {
        border-color: rgba(33,49,76,0.10);
        background: linear-gradient(135deg, rgba(216,106,56,0.18), rgba(34,123,189,0.16));
      }
      .button {
        background: rgba(24, 34, 51, 0.04);
      }
      .button:hover {
        border-color: rgba(33, 49, 76, 0.18);
      }
      .button.primary {
        background: linear-gradient(135deg, rgba(216,106,56,0.18), rgba(216,106,56,0.08));
        border-color: rgba(216,106,56,0.34);
      }
      .button.secondary {
        background: linear-gradient(135deg, rgba(34,123,189,0.16), rgba(34,123,189,0.06));
        border-color: rgba(34,123,189,0.30);
      }
      .button.warn {
        background: linear-gradient(135deg, rgba(209,78,92,0.16), rgba(209,78,92,0.06));
        border-color: rgba(209,78,92,0.28);
      }
      .workspace-sticky::before {
        background: linear-gradient(180deg, rgba(247,250,252,0.88) 0%, rgba(240,245,250,0.74) 82%, rgba(240,245,250,0.45) 100%);
        border-color: rgba(33,49,76,0.08);
      }
      .topnav {
        background: rgba(255,255,255,0.64);
        border-color: rgba(33,49,76,0.10);
        box-shadow: inset 0 1px 0 rgba(255,255,255,0.70);
      }
      .tab.active {
        border-color: rgba(33,49,76,0.10);
        background: rgba(24,34,51,0.06);
        box-shadow: inset 0 1px 0 rgba(255,255,255,0.78);
      }
      .log-panel {
        background: rgba(244,248,252,0.95);
      }
      .toggle,
      input[type="text"],
      input[type="number"],
      input[type="password"],
      textarea,
      select {
        background: rgba(24,34,51,0.03);
      }
      .toast {
        background: rgba(255,255,255,0.95);
      }
      .modal-backdrop {
        background: rgba(232, 238, 245, 0.72);
      }
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100%; height: 100%; }
    body {
      font: 14px/1.45 var(--font-body);
      color: var(--text);
      background:
        radial-gradient(circle at top left, rgba(255,135,91,0.16), transparent 28%),
        radial-gradient(circle at 88% 10%, rgba(77,184,255,0.14), transparent 26%),
        linear-gradient(180deg, #0e1015 0%, #161922 42%, #0f1218 100%);
      letter-spacing: 0.01em;
    }
    button, input, textarea, select { font: inherit; }
    a { color: inherit; }
    .shell {
      max-width: 1680px;
      margin: 0 auto;
      padding: 28px;
      height: 100vh;
      overflow: hidden;
    }
    .hero, .panel, .card, .repo-card, .editor-section, .stack {
      border: 1px solid var(--line);
      background: var(--panel);
      box-shadow: var(--shadow);
    }
    .hero {
      position: relative;
      overflow: hidden;
      border-radius: 24px;
      padding: 16px 18px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
      background:
        linear-gradient(135deg, rgba(255,135,91,0.14), rgba(77,184,255,0.05) 52%, rgba(255,224,130,0.06)),
        var(--panel-2);
    }
    .hero::after {
      content: "";
      position: absolute;
      inset: auto -8% -36% 34%;
      height: 180px;
      background: linear-gradient(90deg, rgba(255,135,91,0), rgba(255,135,91,0.25), rgba(77,184,255,0));
      transform: rotate(-8deg);
      filter: blur(18px);
      pointer-events: none;
    }
    .hero-header {
      display: flex;
      justify-content: space-between;
      gap: 24px;
      align-items: flex-start;
    }
    .hero-brand {
      display: inline-flex;
      align-items: center;
      gap: 12px;
    }
    .hero-glyph {
      width: 34px;
      height: 34px;
      object-fit: contain;
      flex: none;
    }
    .hero h1 {
      margin: 0;
      font: 600 32px/0.92 var(--font-display);
      letter-spacing: -0.03em;
      max-width: 10ch;
    }
    .hero-subtitle { display: none; }
    .panel h2, .editor-section h3 {
      margin: 0 0 12px;
      font: 700 20px/1.1 var(--font-body);
      letter-spacing: -0.02em;
      color: var(--text);
    }
    .section-title {
      display: flex;
      align-items: center;
      gap: 10px;
      line-height: 1.1;
      color: var(--text);
    }
    .section-title span {
      color: var(--text);
    }
    .section-title .icon {
      width: 18px;
      height: 18px;
      color: var(--muted);
    }
    .status-title {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      font-size: 24px;
      line-height: 1.05;
    }
    .status-title .icon {
      width: 20px;
      height: 20px;
      color: var(--muted);
      flex: none;
      align-self: center;
    }
    .hero-stats {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 0;
      justify-content: flex-end;
    }
    .summary-pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      min-height: 38px;
      border-radius: 999px;
      padding: 8px 12px;
      background: rgba(255,255,255,0.04);
      border: 1px solid rgba(255,255,255,0.08);
      color: rgba(255,255,255,0.96);
      font: 12px/1 var(--font-mono);
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    .summary-pill .divider {
      color: var(--muted);
      opacity: 0.7;
    }
    button.summary-pill {
      appearance: none;
      -webkit-appearance: none;
      cursor: pointer;
      font: inherit;
    }
    .summary-pill .muted {
      color: rgba(255,255,255,0.66);
    }
    .mobile-sidebar-toggle {
      display: none;
    }
    .mobile-sidebar-overlay {
      display: none;
    }
    .main-grid {
      display: grid;
      grid-template-columns: 372px minmax(0, 1fr);
      gap: 18px;
      align-items: stretch;
      height: calc(100vh - 56px);
    }
    .stack {
      border-radius: 24px;
      padding: 18px;
      background: rgba(16, 20, 28, 0.92);
      height: 100%;
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }
    main {
      min-height: 0;
      overflow: hidden;
    }
    .stack-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 12px;
    }
    .stack-header .title {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      font: 600 22px/1 var(--font-display);
      letter-spacing: -0.03em;
    }
    .stack-actions {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-left: auto;
    }
    .repo-list {
      display: grid;
      gap: 10px;
      align-content: start;
      align-items: start;
      grid-auto-rows: max-content;
      flex: 1 1 auto;
      min-height: 0;
      overflow: auto;
      padding-right: 4px;
    }
    .stack-footer {
      padding-top: 14px;
      margin-top: 14px;
      border-top: 1px solid rgba(255,255,255,0.08);
      display: flex;
      justify-content: center;
    }
    .repo-card {
      border-radius: 18px;
      padding: 8px 10px;
      background:
        linear-gradient(180deg, rgba(255,255,255,0.03), rgba(255,255,255,0)),
        rgba(17, 21, 30, 0.92);
      cursor: pointer;
      transition: transform 140ms ease, border-color 140ms ease, background 140ms ease;
      min-width: 0;
      width: 100%;
    }
    .repo-card:hover { transform: translateY(-1px); border-color: var(--line-strong); }
    .repo-card.active {
      border-color: rgba(255,135,91,0.52);
      background:
        linear-gradient(180deg, rgba(255,135,91,0.16), rgba(255,135,91,0.04)),
        rgba(24, 20, 20, 0.94);
    }
    .repo-head {
      display: flex;
      gap: 10px;
      align-items: flex-start;
      padding: 2px 2px 0;
    }
    .repo-icon {
      width: 32px;
      height: 32px;
      border-radius: 10px;
      background: linear-gradient(135deg, rgba(255,135,91,0.26), rgba(77,184,255,0.24));
      border: 1px solid rgba(255,255,255,0.1);
      object-fit: cover;
      flex: none;
    }
    .repo-name {
      margin: 0;
      font-size: 14px;
      line-height: 1.2;
      font-weight: 700;
    }
    .repo-meta, .muted {
      color: var(--muted);
    }
    .repo-meta {
      font-size: 11px;
      margin-top: 2px;
      line-height: 1.25;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .repo-status-row {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-top: 6px;
      padding: 0 2px 2px;
      min-width: 0;
    }
    .repo-card .badge {
      padding: 4px 7px;
      font-size: 10px;
    }
    .repo-status-row .repo-meta {
      margin-top: 0;
      min-width: 0;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      flex: 1 1 auto;
    }
    .repo-status-row .badge {
      flex: 0 1 auto;
      min-width: 0;
      max-width: 48%;
    }
    .repo-card .badge.icon-only {
      width: 24px;
      height: 24px;
      padding: 4px;
      justify-content: center;
      max-width: none;
    }
    .repo-card .badge.icon-only span:last-child {
      display: none;
    }
    .repo-status-row .badge span:last-child {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .badges, .toolbar, .row, .metrics, .inline-icon {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
    }
    .badges { margin-top: 10px; }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      border-radius: 999px;
      padding: 5px 9px;
      border: 1px solid rgba(255,255,255,0.08);
      background: rgba(255,255,255,0.04);
      color: var(--muted);
      font: 11px/1 var(--font-mono);
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .icon {
      width: 16px;
      height: 16px;
      flex: none;
      display: inline-block;
      vertical-align: middle;
    }
    .icon svg {
      width: 100%;
      height: 100%;
      display: block;
      stroke: currentColor;
      fill: none;
      stroke-width: 1.8;
      stroke-linecap: round;
      stroke-linejoin: round;
    }
    .badge.success { color: var(--success); }
    .badge.warning { color: var(--warning); }
    .badge.danger { color: var(--danger); }
    .badge.live { color: var(--accent-2); }
    .toolbar {
      margin-top: 14px;
      gap: 10px;
    }
    .button {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      border: 1px solid rgba(255,255,255,0.12);
      background: rgba(255,255,255,0.04);
      color: var(--text);
      border-radius: 14px;
      padding: 10px 14px;
      cursor: pointer;
      transition: transform 120ms ease, border-color 120ms ease, background 120ms ease;
    }
    .button:hover { transform: translateY(-1px); border-color: rgba(255,255,255,0.22); }
    .button.primary {
      background: linear-gradient(135deg, rgba(255,135,91,0.28), rgba(255,135,91,0.12));
      border-color: rgba(255,135,91,0.46);
    }
    .button.secondary {
      background: linear-gradient(135deg, rgba(77,184,255,0.22), rgba(77,184,255,0.08));
      border-color: rgba(77,184,255,0.42);
    }
    .button.warn {
      background: linear-gradient(135deg, rgba(255,109,122,0.26), rgba(255,109,122,0.08));
      border-color: rgba(255,109,122,0.42);
    }
    .panel {
      border-radius: 24px;
      padding: 22px;
      background: rgba(16, 20, 28, 0.9);
      min-width: 0;
    }
    .panel + .panel { margin-top: 18px; }
    .workspace {
      display: grid;
      gap: 22px;
      height: 100%;
      overflow: auto;
      padding-right: 6px;
      align-content: start;
      background: transparent;
    }
    .workspace-sticky {
      position: sticky;
      top: 0;
      z-index: 8;
      display: grid;
      gap: 14px;
      padding: 0;
      background: none;
      border-bottom: none;
      border-radius: 24px;
      isolation: isolate;
      overflow: visible;
    }
    .workspace-sticky::before {
      content: "";
      position: absolute;
      inset: 0;
      border-radius: inherit;
      background: linear-gradient(180deg, rgba(16,20,28,0.82) 0%, rgba(16,20,28,0.7) 82%, rgba(16,20,28,0.38) 100%);
      backdrop-filter: blur(14px);
      border: 1px solid rgba(255,255,255,0.04);
      pointer-events: none;
      z-index: -1;
    }
    .topnav, .subnav {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-bottom: 0;
    }
    .topnav {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 6px;
      padding: 3px;
      margin: 0 14px 0 19px;
      margin-bottom: 20px;
      border-radius: 16px;
      background: rgba(8, 10, 15, 0.78);
      border: 1px solid rgba(255,255,255,0.07);
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.03);
      width: auto;
      max-width: 100%;
    }
    .tab {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      width: 100%;
      border: 1px solid transparent;
      background: transparent;
      color: var(--muted);
      border-radius: 9px;
      padding: 7px 10px;
      cursor: pointer;
      font: 600 12px/1 var(--font-body);
      letter-spacing: -0.01em;
    }
    .tab.active {
      color: var(--text);
      border-color: rgba(255,255,255,0.1);
      background: rgba(255,255,255,0.09);
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.07);
    }
    .tab-pane[hidden] { display: none; }
    .hero-brand {
      display: flex;
      align-items: center;
      gap: 14px;
      min-width: 0;
    }
    .hero-brand h1 {
      margin: 0;
      line-height: 0.95;
    }
    .hero-glyph {
      width: 30px;
      height: 30px;
      flex: 0 0 auto;
      display: block;
      object-fit: contain;
      filter: drop-shadow(0 8px 18px rgba(0,0,0,0.22));
    }
    .repo-subhead {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      min-width: 0;
      padding: 2px 14px 0 19px;
    }
    .repo-subhead-main {
      display: flex;
      align-items: center;
      gap: 12px;
      min-width: 0;
    }
    .repo-subhead-actions {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-left: auto;
    }
    .repo-subhead-copy {
      min-width: 0;
      display: grid;
      gap: 4px;
    }
    .repo-subhead-copy strong {
      font: 600 20px/1.05 var(--font-display);
      letter-spacing: -0.02em;
      color: var(--text);
    }
    .repo-subhead-copy .tiny {
      line-height: 1.2;
    }
    .repo-subhead-icon {
      width: 38px;
      height: 38px;
      border-radius: 10px;
      object-fit: cover;
      flex: none;
      background: rgba(255,255,255,0.05);
    }
    .panel-title {
      display: flex;
      justify-content: space-between;
      align-items: flex-end;
      gap: 16px;
      margin-bottom: 18px;
    }
    .panel-title h2 {
      margin: 0;
      font: 600 24px/1.05 var(--font-display);
      color: var(--text);
      letter-spacing: -0.03em;
    }
    .grid {
      display: grid;
      gap: 12px;
    }
    .grid.two { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .grid.three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    .card {
      border-radius: 18px;
      padding: 18px;
      background: rgba(255,255,255,0.03);
    }
    .card strong {
      display: block;
      font-size: 21px;
      margin-top: 6px;
    }
    .progress {
      margin-top: 10px;
      height: 9px;
      border-radius: 999px;
      overflow: hidden;
      background: rgba(255,255,255,0.06);
    }
    .progress > span {
      display: block;
      height: 100%;
      background: linear-gradient(90deg, var(--accent), var(--accent-2));
      border-radius: inherit;
    }
    .collection {
      display: grid;
      gap: 10px;
    }
    .summary-grid {
      display: grid;
      grid-template-columns: 1.1fr .9fr;
      gap: 12px;
    }
    .item {
      border-radius: 16px;
      padding: 14px;
      border: 1px solid rgba(255,255,255,0.06);
      background: rgba(255,255,255,0.03);
    }
    .item h4 {
      margin: 0 0 6px;
      font-size: 14px;
    }
    .item p {
      margin: 6px 0 0;
      color: var(--muted);
    }
    .editor {
      display: grid;
      gap: 20px;
    }
    .section-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 14px;
    }
    .section-header h3 {
      margin: 0;
    }
    .section-toggle {
      padding: 8px 12px;
      border-radius: 999px;
      font: 600 12px/1 var(--font-body);
    }
    .summary-list {
      display: grid;
      gap: 10px;
    }
    .summary-row {
      display: grid;
      gap: 3px;
      padding: 10px 12px;
      border-radius: 14px;
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.05);
    }
    .summary-row-label {
      font: 11px/1.1 var(--font-mono);
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--muted);
    }
    .summary-row-value {
      color: var(--text);
      word-break: break-word;
    }
    .log-panel {
      border-radius: 16px;
      min-height: 190px;
      max-height: 260px;
      overflow: auto;
      background: rgba(8, 10, 15, 0.72);
      border: 1px solid rgba(255,255,255,0.06);
      padding: 12px;
      font: 12px/1.45 var(--font-mono);
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      word-break: break-word;
      color: var(--text);
      min-width: 0;
    }
    .avatar-row {
      display: flex;
      align-items: center;
      gap: 8px;
      min-width: 0;
    }
    .avatar {
      width: 22px;
      height: 22px;
      border-radius: 999px;
      overflow: hidden;
      background: rgba(255,255,255,0.08);
      flex: none;
    }
    .avatar img {
      width: 100%;
      height: 100%;
      display: block;
      object-fit: cover;
    }
    .avatar-row a,
    .avatar-row span {
      color: inherit;
      text-decoration: none;
    }
    .status-card-head {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 8px;
    }
    .editor-section {
      border-radius: 24px;
      padding: 20px;
      background: rgba(14, 18, 26, 0.94);
      min-width: 0;
    }
    .editor-section h3 {
      color: var(--accent-3);
    }
    .field-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;
    }
    .field-grid.single { grid-template-columns: 1fr; }
    label.field {
      display: grid;
      gap: 6px;
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.1em;
      font-family: var(--font-mono);
    }
    input[type="text"], input[type="number"], input[type="password"], textarea, select {
      width: 100%;
      border-radius: 14px;
      border: 1px solid rgba(255,255,255,0.1);
      background: rgba(255,255,255,0.04);
      color: var(--text);
      padding: 11px 12px;
      min-height: 44px;
    }
    textarea {
      min-height: 120px;
      resize: vertical;
      font-family: var(--font-mono);
      font-size: 12px;
      line-height: 1.45;
    }
    .toggle {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 12px 14px;
      min-height: 48px;
      border-radius: 14px;
      border: 1px solid rgba(255,255,255,0.08);
      background: rgba(255,255,255,0.04);
      color: var(--text);
      font-size: 13px;
      text-transform: none;
      letter-spacing: 0;
      font-family: var(--font-body);
    }
    .toggle input { width: 18px; height: 18px; }
    .toast-region {
      position: fixed;
      top: 20px;
      right: 20px;
      z-index: 26;
      display: grid;
      gap: 10px;
      width: min(360px, calc(100vw - 32px));
      pointer-events: none;
    }
    .toast {
      border-radius: 16px;
      padding: 13px 14px;
      font-weight: 600;
      border: 1px solid rgba(255,255,255,0.08);
      background: rgba(18, 22, 30, 0.96);
      box-shadow: 0 18px 40px rgba(0,0,0,0.32);
      pointer-events: auto;
      animation: toast-in 180ms ease-out;
    }
    .toast.ok { border-color: rgba(82,212,159,0.28); color: var(--success); }
    .toast.error { border-color: rgba(255,109,122,0.36); color: var(--danger); }
    @keyframes toast-in {
      from { opacity: 0; transform: translateY(-8px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .floating-save {
      position: fixed;
      right: 28px;
      bottom: 28px;
      z-index: 25;
    }
    .modal-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(7, 9, 13, 0.72);
      backdrop-filter: blur(8px);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      z-index: 30;
    }
    .modal-card {
      width: min(920px, 100%);
      max-height: calc(100vh - 48px);
      overflow: auto;
      border-radius: 24px;
      border: 1px solid var(--line-strong);
      background: rgba(16, 20, 28, 0.98);
      box-shadow: 0 28px 70px rgba(0,0,0,0.44);
      padding: 22px;
    }
    .modal-card.settings-modal {
      width: min(1180px, 100%);
      padding: 20px 20px 22px;
    }
    .modal-title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 18px;
    }
    .modal-title h2 {
      margin: 0;
      font: 600 30px/1 var(--font-display);
      color: var(--text);
      letter-spacing: -0.03em;
    }
    .settings-shell {
      display: grid;
      gap: 18px;
    }
    .settings-tabs {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 10px;
      padding: 6px;
      border-radius: 22px;
      background: rgba(10, 13, 18, 0.78);
      border: 1px solid rgba(255,255,255,0.07);
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.04);
    }
    .settings-tab {
      display: grid;
      justify-items: center;
      gap: 8px;
      padding: 14px 12px 12px;
      border-radius: 16px;
      border: 1px solid transparent;
      background: transparent;
      color: var(--muted);
      cursor: pointer;
      text-align: center;
      font: 600 13px/1.1 var(--font-body);
    }
    .settings-tab .icon {
      width: 18px;
      height: 18px;
    }
    .settings-tab.active {
      color: var(--text);
      border-color: rgba(255,255,255,0.1);
      background: rgba(255,255,255,0.09);
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.06);
    }
    .settings-pane-grid {
      display: grid;
      grid-template-columns: minmax(0, 1.2fr) minmax(320px, 0.8fr);
      gap: 16px;
      align-items: start;
    }
    .settings-pane-grid.single {
      grid-template-columns: 1fr;
    }
    .settings-stack {
      display: grid;
      gap: 16px;
    }
    .settings-card {
      border-radius: 22px;
      padding: 20px;
      background: rgba(14, 18, 26, 0.92);
      border: 1px solid rgba(255,255,255,0.06);
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.02);
    }
    .settings-card .section-title {
      margin-bottom: 16px;
    }
    .settings-card .toolbar {
      margin-top: 16px;
    }
    .settings-note {
      margin-top: 12px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
    }
    .security-list {
      display: grid;
      gap: 10px;
    }
    .security-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
      padding: 12px 14px;
      border-radius: 16px;
      background: rgba(255,255,255,0.035);
      border: 1px solid rgba(255,255,255,0.06);
      min-width: 0;
    }
    .security-row.compact {
      align-items: flex-start;
    }
    .security-row-main {
      display: grid;
      gap: 4px;
      min-width: 0;
    }
    .security-row-main strong {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .security-row-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: flex-end;
      flex: none;
    }
    .audit-card {
      max-height: min(680px, calc(100vh - 260px));
      overflow: auto;
    }
    .audit-list {
      display: grid;
      gap: 9px;
    }
    .audit-row {
      display: grid;
      grid-template-columns: 30px minmax(0, 1fr);
      gap: 10px;
      align-items: start;
      padding: 10px 12px;
      border-radius: 15px;
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.055);
    }
    .audit-icon {
      width: 30px;
      height: 30px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border-radius: 10px;
      background: rgba(255,255,255,0.05);
      color: var(--muted);
    }
    .audit-copy {
      display: grid;
      gap: 4px;
      min-width: 0;
    }
    .audit-line {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 10px;
      min-width: 0;
    }
    .audit-line strong {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .invite-card {
      display: grid;
      gap: 5px;
      margin-top: 14px;
      padding: 12px 14px;
      border-radius: 16px;
      background: rgba(77,184,255,0.08);
      border: 1px solid rgba(77,184,255,0.20);
      word-break: break-word;
    }
    .invite-card a {
      color: var(--accent-2);
      text-decoration: none;
    }
    .dim { opacity: 0.68; }
    .empty {
      padding: 24px;
      text-align: center;
      color: var(--muted);
      border: 1px dashed rgba(255,255,255,0.12);
      border-radius: 18px;
    }
    .tiny {
      font-size: 12px;
      color: var(--muted);
    }
    .link-row {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 8px;
    }
    .link-row a {
      color: var(--accent-2);
      text-decoration: none;
    }
    .mono { font-family: var(--font-mono); }
    @media (prefers-color-scheme: light) {
      body {
        background:
          radial-gradient(circle at top left, rgba(216,106,56,0.14), transparent 28%),
          radial-gradient(circle at 88% 10%, rgba(34,123,189,0.12), transparent 26%),
          linear-gradient(180deg, #f7fafc 0%, #edf3f8 44%, #e7eef5 100%);
      }
      .hero,
      .panel,
      .card,
      .repo-card,
      .editor-section,
      .stack,
      .summary-row,
      .item,
      .modal-card {
        border-color: rgba(33, 49, 76, 0.10);
        box-shadow: var(--shadow);
      }
      .hero {
        background:
          linear-gradient(135deg, rgba(216,106,56,0.12), rgba(34,123,189,0.05) 52%, rgba(147,107,16,0.06)),
          rgba(255,255,255,0.90);
      }
      .hero::after {
        background: linear-gradient(90deg, rgba(216,106,56,0), rgba(216,106,56,0.16), rgba(34,123,189,0));
      }
      .summary-pill {
        background: rgba(24,34,51,0.04);
        border-color: rgba(33,49,76,0.10);
        color: var(--text);
      }
      .summary-pill .muted {
        color: var(--muted);
      }
      .stack {
        background: rgba(255,255,255,0.78);
      }
      .stack-footer {
        border-top-color: rgba(33,49,76,0.10);
      }
      .repo-card {
        background:
          linear-gradient(180deg, rgba(24,34,51,0.02), rgba(24,34,51,0)),
          rgba(255,255,255,0.82);
      }
      .repo-card.active {
        border-color: rgba(216,106,56,0.34);
        background:
          linear-gradient(180deg, rgba(216,106,56,0.12), rgba(216,106,56,0.03)),
          rgba(255,250,247,0.96);
      }
      .repo-icon,
      .repo-subhead-icon {
        border-color: rgba(33,49,76,0.10);
        background: linear-gradient(135deg, rgba(216,106,56,0.18), rgba(34,123,189,0.16));
      }
      .repo-subhead-icon,
      .avatar {
        background-color: rgba(24,34,51,0.06);
      }
      .badge {
        background: rgba(24,34,51,0.04);
        border-color: rgba(33,49,76,0.10);
        color: var(--muted);
      }
      .button {
        background: rgba(24,34,51,0.04);
        border-color: rgba(33,49,76,0.12);
      }
      .button:hover {
        border-color: rgba(33,49,76,0.18);
      }
      .button.primary {
        background: linear-gradient(135deg, rgba(216,106,56,0.18), rgba(216,106,56,0.08));
        border-color: rgba(216,106,56,0.34);
      }
      .button.secondary {
        background: linear-gradient(135deg, rgba(34,123,189,0.16), rgba(34,123,189,0.06));
        border-color: rgba(34,123,189,0.30);
      }
      .button.warn {
        background: linear-gradient(135deg, rgba(209,78,92,0.16), rgba(209,78,92,0.06));
        border-color: rgba(209,78,92,0.28);
      }
      .workspace-sticky::before {
        background: linear-gradient(180deg, rgba(247,250,252,0.88) 0%, rgba(240,245,250,0.74) 82%, rgba(240,245,250,0.45) 100%);
        border-color: rgba(33,49,76,0.08);
      }
      .topnav {
        background: rgba(255,255,255,0.64);
        border-color: rgba(33,49,76,0.10);
        box-shadow: inset 0 1px 0 rgba(255,255,255,0.70);
      }
      .settings-tabs {
        background: rgba(255,255,255,0.72);
        border-color: rgba(33,49,76,0.10);
        box-shadow: inset 0 1px 0 rgba(255,255,255,0.78);
      }
      .tab.active {
        border-color: rgba(33,49,76,0.10);
        background: rgba(24,34,51,0.06);
        box-shadow: inset 0 1px 0 rgba(255,255,255,0.78);
      }
      .settings-tab.active {
        border-color: rgba(33,49,76,0.10);
        background: rgba(24,34,51,0.06);
        box-shadow: inset 0 1px 0 rgba(255,255,255,0.78);
      }
      .card,
      .item,
      .summary-row {
        background: rgba(255,255,255,0.72);
        border-color: rgba(33,49,76,0.08);
      }
      .panel,
      .editor-section,
      .stack,
      .settings-card,
      .security-row,
      .audit-row {
        background: rgba(255,255,255,0.80);
      }
      .audit-icon {
        background: rgba(24,34,51,0.05);
      }
      .invite-card {
        background: rgba(34,123,189,0.08);
        border-color: rgba(34,123,189,0.18);
      }
      .progress {
        background: rgba(24,34,51,0.08);
      }
      .editor-section {
        background: rgba(244,248,252,0.95);
      }
      .editor-section h3,
      .modal-title h2 {
        color: var(--text);
      }
      .log-panel {
        background: rgba(244,248,252,0.95);
        border-color: rgba(33,49,76,0.08);
      }
      .section-title .icon,
      .status-title .icon {
        color: var(--muted);
      }
      .avatar {
        background: rgba(24,34,51,0.08);
      }
      input[type="text"],
      input[type="number"],
      input[type="password"],
      textarea,
      select,
      .toggle {
        background: rgba(24,34,51,0.03);
        border-color: rgba(33,49,76,0.10);
      }
      .toast {
        background: rgba(255,255,255,0.95);
        border-color: rgba(33,49,76,0.10);
      }
      .modal-backdrop {
        background: rgba(232,238,245,0.72);
      }
      .modal-card {
        background: rgba(255,255,255,0.94);
      }
      .empty {
        border-color: rgba(33,49,76,0.16);
        background: rgba(255,255,255,0.48);
      }
    }
    @media (max-width: 1440px) {
      .main-grid { grid-template-columns: 344px minmax(0, 1fr); }
      .settings-pane-grid {
        grid-template-columns: 1fr;
      }
    }
    @media (max-width: 1040px) {
      .masthead, .grid.two, .grid.three, .field-grid, .summary-grid, .hero-stats { grid-template-columns: 1fr; }
      .shell { padding: 16px; }
      .shell { height: auto; overflow: visible; }
      .main-grid { display: block; height: auto; }
      .workspace { overflow: visible; }
      .settings-tabs { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .workspace-sticky {
        position: sticky;
        top: 12px;
        z-index: 12;
        background: none;
        padding-bottom: 0;
        border-bottom: none;
      }
      .topnav { margin: 0 0 20px; width: 100%; }
      .stack {
        position: fixed;
        top: 16px;
        left: 16px;
        bottom: 16px;
        width: min(344px, calc(100vw - 56px));
        max-height: none;
        z-index: 40;
        transform: translateX(calc(-100% - 18px));
        transition: transform 180ms ease;
        box-shadow: 0 28px 70px rgba(0,0,0,0.44);
      }
      body.sidebar-open .stack {
        transform: translateX(0);
      }
      .mobile-sidebar-overlay {
        display: block;
        position: fixed;
        inset: 0;
        background: rgba(7, 9, 13, 0);
        backdrop-filter: none;
        opacity: 0;
        pointer-events: none;
        transition: opacity 180ms ease, background 180ms ease, backdrop-filter 180ms ease;
        z-index: 35;
      }
      body.sidebar-open .mobile-sidebar-overlay {
        background: rgba(7, 9, 13, 0.48);
        backdrop-filter: blur(4px);
        opacity: 1;
        pointer-events: auto;
      }
      .mobile-sidebar-toggle {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        border: 1px solid rgba(255,255,255,0.10);
        background: rgba(255,255,255,0.05);
        color: var(--text);
        border-radius: 14px;
        padding: 10px 12px;
      }
      .hero-header { flex-direction: column; }
      .hero { display: grid; justify-content: stretch; gap: 10px; }
      .hero-header {
        flex-direction: row;
        align-items: center;
      }
      .hero h1 { font-size: 34px; }
      .hero-stats { justify-content: flex-start; }
      .repo-subhead {
        padding-left: 14px;
        padding-right: 14px;
      }
      .repo-subhead-actions {
        flex-wrap: wrap;
        justify-content: flex-end;
      }
      .floating-save {
        right: 16px;
        bottom: 16px;
      }
      .toast-region {
        top: 12px;
        right: 12px;
      }
    }
  </style>
</head>
<body>
  <div class="mobile-sidebar-overlay" data-action="close-sidebar"></div>
  <div class="shell">
    <section class="main-grid">
      <aside class="stack" id="repo-sidebar">
        <div class="stack-header">
          <div class="title"><span class="icon"><svg viewBox="0 0 24 24"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4H20v16H6.5A2.5 2.5 0 0 0 4 22z"/><path d="M8 8h8"/><path d="M8 12h8"/></svg></span><span>Repositories</span></div>
          <div class="stack-actions">
            <button class="button secondary" data-action="poll-all"><span class="icon"><svg viewBox="0 0 24 24"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/></svg></span><span>Check All</span></button>
          </div>
        </div>
        <div id="repo-list" class="repo-list"></div>
        <div class="stack-footer">
          <button class="button primary" data-action="open-add-repo"><span class="icon"><svg viewBox="0 0 24 24"><path d="M12 5v14"/><path d="M5 12h14"/></svg></span><span>Add Repository</span></button>
        </div>
      </aside>

      <main>
        <div class="workspace">
          <div class="workspace-sticky">
            <section class="masthead">
              <div class="hero">
                <div class="hero-header">
                  <button class="mobile-sidebar-toggle" type="button" data-action="open-sidebar"><span class="icon"><svg viewBox="0 0 24 24"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4H20v16H6.5A2.5 2.5 0 0 0 4 22z"/><path d="M8 8h8"/><path d="M8 12h8"/></svg></span><span>Repositories</span></button>
                  <div class="hero-brand">
                    <picture>
                      <source media="(prefers-color-scheme: dark)" srcset="/assets/glyph-dark.png">
                      <img class="hero-glyph" src="/assets/glyph-light.png" alt="">
                    </picture>
                    <h1>ShipHook</h1>
                  </div>
                </div>
                <div id="overview-stats" class="hero-stats"></div>
              </div>
            </section>
            <div id="repo-subhead" class="repo-subhead"></div>
            <div class="topnav" id="top-nav"></div>
          </div>
          <section class="tab-pane" id="pane-status"></section>
          <section class="tab-pane" id="pane-builds"></section>
          <section class="tab-pane" id="pane-configuration"></section>
        </div>
      </main>
    </section>
  </div>
  <div id="toast-root" class="toast-region"></div>
  <div id="floating-save-root"></div>
  <div id="modal-root"></div>

  <script>
    const state = {
      snapshot: null,
      draftConfig: null,
      selectedRepoId: null,
      activePane: 'status',
      configSections: {
        repoSetup: false,
        buildAutomation: false,
        sparkle: false,
        webhooks: false,
        advanced: false
      },
      addRepoWizardOpen: false,
      settingsModalOpen: false,
      settingsPane: 'general',
      securityState: null,
      securityLoading: false,
      securityStatus: '',
      securityInviteLink: null,
      explorerModal: null,
      mobileSidebarOpen: false,
      addRepoInspectionPreview: null,
      toasts: [],
      toastTimerId: null,
      saving: false,
      refreshTimerId: null,
      refreshInFlight: false
    };

    const globalDefaults = {
      pollIntervalSeconds: 300,
      githubToken: '',
      githubTokenEnvVar: 'GITHUB_TOKEN',
      generatedDataRetentionCount: 3,
      autoPauseFailureCount: 3,
      webDashboardEnabled: false,
      webDashboardPort: 8787
    };

    const repositoryDefaults = {
      id: '',
      name: 'New Repository',
      isEnabled: true,
      owner: '',
      repo: '',
      branch: 'main',
      localCheckoutPath: '',
      workingDirectory: '',
      buildOnFirstSeen: false,
      buildMode: 'xcodeArchive',
      xcode: {
        projectPath: '',
        workspacePath: '',
        scheme: '',
        appName: '',
        configuration: 'Release',
        archivePath: '',
        artifactPath: ''
      },
      shell: {
        command: '',
        artifactPath: ''
      },
      publishCommand: '',
      releaseNotesPath: '',
      preferExistingReleaseNotesFile: false,
      githubTokenEnvVar: '',
      environment: {},
      versionStrategy: 'shortSHATimestamp',
      sparkle: {
        appcastURL: '',
        autoIncrementBuild: false,
        skipIfVersionIsNotNewer: true,
        betaIconPath: ''
      },
      notifications: {
        discordWebhookURL: '',
        postOnSuccess: false,
        postOnFailure: false
      },
      signing: {
        developmentTeam: '',
        codeSignIdentity: '',
        codeSignStyle: 'automatic',
        notarizationProfile: ''
      }
    };

    const notarizationDraft = {
      profileName: '',
      appleID: '',
      teamID: '',
      appSpecificPassword: ''
    };

    const addRepoDraft = {
      localCheckoutPath: '',
      fallbackOwner: '',
      fallbackRepo: '',
      fallbackBranch: 'main',
      selectedScheme: ''
    };

    const securityDraft = {
      currentPassword: '',
      newPassword: '',
      inviteUsername: ''
    };

    async function fetchState({ preserveDraft = true, clearStatus = true } = {}) {
      const response = await fetch('/api/state');
      if (response.status === 401) {
        window.location.href = '/';
        return;
      }
      const snapshot = await response.json();
      applySnapshot(snapshot, { preserveDraft });
      if (clearStatus) {
        setStatus(null);
      }
    }

    async function fetchSecurityState() {
      state.securityLoading = true;
      try {
        const response = await fetch('/api/auth/security-state');
        if (response.status === 401) {
          window.location.href = '/';
          return;
        }
        const payload = await response.json();
        if (!response.ok || payload.ok === false) {
          throw new Error(payload.error || 'Could not load account security.');
        }
        state.securityState = payload;
      } finally {
        state.securityLoading = false;
      }
    }

    function applySnapshot(snapshot, { preserveDraft = true } = {}) {
      const shouldPreserveDraft = preserveDraft && !!state.snapshot?.global?.hasUnsavedChanges && !!state.draftConfig;
      state.snapshot = snapshot;
      if (!shouldPreserveDraft) {
        state.draftConfig = makeDraftConfig(snapshot);
      }
      if (!state.selectedRepoId || !state.draftConfig.repositories.some(repo => repo.id === state.selectedRepoId)) {
        state.selectedRepoId = state.draftConfig.repositories[0]?.id ?? null;
      }
      render();
    }

    function makeDraftConfig(snapshot) {
      return {
        pollIntervalSeconds: snapshot.global.pollIntervalSeconds ?? globalDefaults.pollIntervalSeconds,
        githubToken: snapshot.global.githubToken ?? '',
        githubTokenEnvVar: snapshot.global.githubTokenEnvVar ?? globalDefaults.githubTokenEnvVar,
        generatedDataRetentionCount: snapshot.global.generatedDataRetentionCount ?? globalDefaults.generatedDataRetentionCount,
        autoPauseFailureCount: snapshot.global.autoPauseFailureCount ?? globalDefaults.autoPauseFailureCount,
        webDashboardEnabled: !!snapshot.global.webDashboardEnabled,
        webDashboardPort: snapshot.global.webDashboardPort ?? globalDefaults.webDashboardPort,
        repositories: snapshot.repositories.map(repo => normalizeRepository(repo.configuration))
      };
    }

    function normalizeRepository(repository) {
      const merged = structuredClone(repositoryDefaults);
      const next = { ...merged, ...repository };
      next.workingDirectory = repository.workingDirectory ?? '';
      next.releaseNotesPath = repository.releaseNotesPath ?? '';
      next.githubTokenEnvVar = repository.githubTokenEnvVar ?? '';
      next.xcode = { ...merged.xcode, ...(repository.xcode ?? {}) };
      next.shell = { ...merged.shell, ...(repository.shell ?? {}) };
      next.sparkle = { ...merged.sparkle, ...(repository.sparkle ?? {}) };
      next.notifications = { ...merged.notifications, ...(repository.notifications ?? {}) };
      next.signing = { ...merged.signing, ...(repository.signing ?? {}) };
      next.environment = repository.environment ?? {};
      return next;
    }

    async function runCommand(payload, successMessage) {
      const response = await fetch('/api/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      if (response.status === 401) {
        window.location.href = '/';
        return;
      }
      const data = await response.json();
      if (data.snapshot) {
        applySnapshot(data.snapshot);
      }
      if (!response.ok || data.ok === false) {
        throw new Error(data.error || 'Request failed.');
      }
      state.addRepoInspectionPreview = data.inspectionPreview || null;
      setStatus({ kind: 'ok', message: data.message || successMessage || 'Done.' });
      return data;
    }

    function refreshIntervalMillis() {
      const snapshot = state.snapshot;
      if (!snapshot) return 2000;
      const busy = snapshot.repositories.some(repo => ['building', 'polling'].includes(repo.runtime.activity));
      return busy ? 1500 : 4000;
    }

    function scheduleAutoRefresh() {
      if (state.refreshTimerId) {
        window.clearTimeout(state.refreshTimerId);
        state.refreshTimerId = null;
      }
      state.refreshTimerId = window.setTimeout(runAutoRefresh, refreshIntervalMillis());
    }

    async function runAutoRefresh() {
      if (document.hidden || state.refreshInFlight) {
        scheduleAutoRefresh();
        return;
      }
      state.refreshInFlight = true;
      try {
        await fetchState({ preserveDraft: true, clearStatus: false });
      } catch {
        // Keep the last known UI state; a later refresh can recover.
      } finally {
        state.refreshInFlight = false;
        scheduleAutoRefresh();
      }
    }

    function setStatus(status) {
      if (!status) {
        state.toasts = [];
        scheduleToastDismiss();
        renderStatus();
        return;
      }

      const toast = {
        id: `toast-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        kind: status.kind,
        message: status.message,
        hovered: false
      };
      state.toasts = [...state.toasts, toast].slice(-3);
      scheduleToastDismiss();
      renderStatus();
    }

    function render() {
      document.body.classList.toggle('sidebar-open', !!state.mobileSidebarOpen);
      renderStatus();
      renderOverview();
      renderRepoList();
      renderRepoSubhead();
      renderTopNav();
      renderStatusPane();
      renderBuildsPane();
      renderConfigurationPane();
      renderFloatingSave();
      renderModal();
      wireActionButtons();
    }

    function openSettingsModal(pane = null) {
      state.settingsModalOpen = true;
      state.settingsPane = pane || state.settingsPane || 'general';
      state.addRepoWizardOpen = false;
      state.explorerModal = null;
      render();
      if (state.settingsPane === 'account' && !state.securityState && !state.securityLoading) {
        fetchSecurityState()
          .then(renderModal)
          .catch(error => {
            state.securityStatus = error.message || String(error);
            renderModal();
          });
      }
    }

    function openExplorerModal(kind) {
      state.explorerModal = kind;
      state.settingsModalOpen = false;
      state.addRepoWizardOpen = false;
      render();
    }

    function wireActionButtons() {
      const settingsButton = document.querySelector('[data-action="open-settings"]');
      if (settingsButton) {
        settingsButton.onclick = event => {
          event.preventDefault();
          openSettingsModal();
        };
      }

      const securityButton = document.querySelector('[data-action="open-security"]');
      if (securityButton) {
        securityButton.onclick = event => {
          event.preventDefault();
          openSettingsModal('account');
        };
      }

      document.querySelectorAll('[data-action="open-explorer"]').forEach(button => {
        button.onclick = event => {
          event.preventDefault();
          openExplorerModal(button.dataset.explorer);
        };
      });
    }

    function renderStatus() {
      const node = document.getElementById('toast-root');
      if (!state.toasts.length) {
        node.innerHTML = '';
        return;
      }
      node.innerHTML = state.toasts.map(toast => `
        <div class="toast ${toast.kind}" data-toast-id="${toast.id}">
          ${escapeHtml(toast.message)}
        </div>
      `).join('');
    }

    function renderFloatingSave() {
      const node = document.getElementById('floating-save-root');
      if (!state.snapshot?.global?.hasUnsavedChanges) {
        node.innerHTML = '';
        return;
      }

      node.innerHTML = `
        <div class="floating-save">
          <button class="button primary" data-action="save">${icon('save')}<span>Save Changes</span></button>
        </div>
      `;
    }

    function renderOverview() {
      const statsNode = document.getElementById('overview-stats');
      const snapshot = state.snapshot;
      if (!snapshot) {
        statsNode.innerHTML = '';
        return;
      }

      const total = snapshot.repositories.length;
      const enabled = snapshot.repositories.filter(repo => repo.configuration.isEnabled).length;
      const building = snapshot.repositories.filter(repo => repo.runtime.activity === 'building').length;
      const polling = snapshot.repositories.filter(repo => repo.runtime.activity === 'polling').length;
      const failures = snapshot.repositories.filter(repo => repo.runtime.activity === 'failed').length;
      const queued = snapshot.repositories.filter(repo => repo.runtime.phase === 'queued').length;
      const activeLabel = building > 0
        ? `${building} building`
        : polling > 0
          ? `${polling} checking`
          : failures > 0
            ? `${failures} failing`
            : 'idle';

      const detailParts = [];
      if (queued > 0) detailParts.push(`${queued} queued`);
      if (failures > 0 && building > 0) detailParts.push(`${failures} failing`);

      statsNode.innerHTML = [
        summaryPill('repos', `Repos ${total}`, `${enabled} enabled`),
        summaryPill('activity', `Activity ${activeLabel}`, detailParts.join(' • ')),
        `<button class="summary-pill" type="button" data-action="open-security" title="Account & Security" aria-label="Open Account & Security">${icon('user')}</button>`,
        `<button class="summary-pill" type="button" data-action="open-settings" title="ShipHook Settings" aria-label="Open ShipHook Settings">${icon('gear')}</button>`
      ].join('');

    }

    function renderRepoList() {
      const node = document.getElementById('repo-list');
      const repositories = state.snapshot?.repositories ?? [];
      if (!repositories.length) {
        node.innerHTML = '<div class="empty">No repositories configured yet.</div>';
        return;
      }

      node.innerHTML = repositories.map(repo => {
        const active = repo.id === state.selectedRepoId ? 'active' : '';
        const icon = repo.iconDataURL ? `<img class="repo-icon" src="${repo.iconDataURL}" alt="">` : '<div class="repo-icon"></div>';
        return `
          <article class="repo-card ${active}" data-select-repo="${repo.id}">
            <div class="repo-head">
              ${icon}
              <div style="min-width: 0;">
                <h3 class="repo-name">${escapeHtml(repo.name || repo.id)}</h3>
                <div class="repo-meta">${escapeHtml(repo.runtime.slug)} @ ${escapeHtml(repo.runtime.branch)}</div>
              </div>
            </div>
            <div class="repo-status-row">
              ${repoStatusBadge(repo)}
              <div class="repo-meta">${escapeHtml(repo.runtime.summary || 'No summary')}</div>
            </div>
          </article>
        `;
      }).join('');
    }

    function renderTopNav() {
      const node = document.getElementById('top-nav');
      node.innerHTML = [
        paneTab('status', 'Status'),
        paneTab('builds', 'Builds & Releases'),
        paneTab('configuration', 'Configuration')
      ].join('');

      document.getElementById('pane-status').hidden = state.activePane !== 'status';
      document.getElementById('pane-builds').hidden = state.activePane !== 'builds';
      document.getElementById('pane-configuration').hidden = state.activePane !== 'configuration';
    }

    function renderRepoSubhead() {
      const node = document.getElementById('repo-subhead');
      const repo = selectedRepoSnapshot();
      if (!repo) {
        node.innerHTML = '';
        node.hidden = true;
        return;
      }

      const repoIcon = repo.iconDataURL
        ? `<img class="repo-subhead-icon" src="${repo.iconDataURL}" alt="">`
        : '<div class="repo-subhead-icon"></div>';

      node.hidden = false;
      node.innerHTML = `
        <div class="repo-subhead-main">
          ${repoIcon}
          <div class="repo-subhead-copy">
            <strong>${escapeHtml(repo.name || repo.id)}</strong>
            <div class="tiny">${escapeHtml(repo.runtime.slug)} @ ${escapeHtml(repo.runtime.branch)}</div>
          </div>
        </div>
        <div class="repo-subhead-actions">
          <button class="button secondary" data-action="poll-repo" data-repo-id="${repo.id}">${icon('refresh')}<span>Check Now</span></button>
          <button class="button" data-action="reclone-repo" data-repo-id="${repo.id}">${icon('repo-refresh')}<span>Reclone</span></button>
          <button class="button" data-action="set-repo-enabled" data-repo-id="${repo.id}" data-enabled="${repo.configuration.isEnabled ? 'false' : 'true'}" title="${repo.configuration.isEnabled ? 'Pause repository' : 'Resume repository'}">${icon(repo.configuration.isEnabled ? 'pause' : 'play')}</button>
        </div>
      `;
    }

    function renderModal() {
      const node = document.getElementById('modal-root');
      if (state.settingsModalOpen) {
        node.innerHTML = `
          <div class="modal-backdrop">
            <div class="modal-card settings-modal">
              <div class="modal-title">
                <h2>ShipHook Settings</h2>
                <button class="button" data-action="close-settings">${icon('close')}<span>Close</span></button>
              </div>
              ${renderGlobalForm()}
            </div>
          </div>
        `;
        return;
      }

      if (state.explorerModal) {
        const repo = selectedRepoSnapshot();
        if (!repo) {
          state.explorerModal = null;
          node.innerHTML = '';
          return;
        }

        const builds = repo.recentBuilds.map(build => `
          <div class="item">
            <div class="row" style="justify-content: space-between;">
              <h4>${escapeHtml(build.version)}</h4>
              <div class="tiny">${escapeHtml(formatDate(build.builtAt))}</div>
            </div>
            <div class="tiny">Commit ${escapeHtml(shortSha(build.sha))}</div>
            <p>${escapeHtml(build.summary || 'No summary')}</p>
            ${authorLine(build.authorLogin, build.authorAvatarURL, build.authorProfileURL, 'built this release')}
            ${build.logPath ? `<div class="tiny mono" style="margin-top: 8px;">${escapeHtml(build.logPath)}</div>` : ''}
          </div>
        `).join('');

        const releases = repo.recentReleases.map(release => `
          <div class="item">
            <div class="row" style="justify-content: space-between;">
              <h4>${escapeHtml(release.tagName)}</h4>
              <button class="button ${release.isPrerelease ? '' : 'secondary'}" data-action="rollback" data-repo-id="${repo.id}" data-tag-name="${escapeHtmlAttr(release.tagName)}">Rollback</button>
            </div>
            <div class="tiny">${escapeHtml(release.isPrerelease ? 'Beta' : 'Stable')} · ${escapeHtml(formatDate(release.publishedAt) || 'Unknown date')}</div>
            <p>${escapeHtml(release.name || 'No release title')}</p>
            ${authorLine(release.authorLogin, release.authorAvatarURL, release.authorProfileURL, 'published this release')}
          </div>
        `).join('');

        const isBuilds = state.explorerModal === 'builds';
        node.innerHTML = `
          <div class="modal-backdrop">
            <div class="modal-card">
              <div class="modal-title">
                <h2>${isBuilds ? 'Build Explorer' : 'Release Explorer'}</h2>
                <button class="button" data-action="close-explorer">${icon('close')}<span>Close</span></button>
              </div>
              <div class="collection">
                ${isBuilds ? (builds || '<div class="empty">No builds recorded yet.</div>') : (releases || '<div class="empty">No releases loaded yet.</div>')}
              </div>
            </div>
          </div>
        `;
        return;
      }

      if (!state.addRepoWizardOpen) {
        node.innerHTML = '';
        return;
      }

      const preview = state.addRepoInspectionPreview;
      const schemes = preview?.inspection?.schemes || [];
      if (!addRepoDraft.selectedScheme && schemes.length) {
        addRepoDraft.selectedScheme = preview.inspection.suggestedScheme || schemes[0];
      }

      node.innerHTML = `
        <div class="modal-backdrop">
          <div class="modal-card">
            <div class="modal-title">
              <h2>Add Repository</h2>
              <button class="button" data-action="close-add-repo">${icon('close')}<span>Close</span></button>
            </div>
            <div class="grid two">
              <div class="card">
                <div class="field-grid single">
                  ${textInput('Local Checkout Path', 'addRepo.localCheckoutPath', addRepoDraft.localCheckoutPath)}
                  ${textInput('Fallback Owner', 'addRepo.fallbackOwner', addRepoDraft.fallbackOwner)}
                  ${textInput('Fallback Repo', 'addRepo.fallbackRepo', addRepoDraft.fallbackRepo)}
                  ${textInput('Fallback Branch', 'addRepo.fallbackBranch', addRepoDraft.fallbackBranch)}
                </div>
                <div class="toolbar">
                  <button class="button secondary" data-action="inspect-repo">${icon('search')}<span>Inspect Checkout</span></button>
                </div>
              </div>
              <div class="card">
                ${preview ? `
                  <div class="tiny">Inspection result</div>
                  <strong>${escapeHtml(preview.suggestedRepository.name || preview.suggestedRepository.id)}</strong>
                  <p>${escapeHtml((preview.inspection.owner || addRepoDraft.fallbackOwner || '') + '/' + (preview.inspection.repo || addRepoDraft.fallbackRepo || ''))}</p>
                  <div class="field-grid single" style="margin-top: 12px;">
                    ${schemes.length ? selectInput('Build Scheme', 'addRepo.selectedScheme', addRepoDraft.selectedScheme, schemes.map(scheme => [scheme, scheme])) : readOnlyInput('Build Scheme', addRepoDraft.selectedScheme || preview.inspection.suggestedScheme || 'None found')}
                  </div>
                  <div class="link-row tiny">
                    <span>Workspace: ${escapeHtml(preview.inspection.workspacePath || 'None')}</span>
                    <span>Project: ${escapeHtml(preview.inspection.projectPath || 'None')}</span>
                  </div>
                  <div class="toolbar">
                    <button class="button primary" data-action="confirm-add-repo">${icon('plus')}<span>Add Repository</span></button>
                  </div>
                ` : `
                  <div class="empty">Point ShipHook at a local checkout, inspect it, then add the generated repository configuration.</div>
                `}
              </div>
            </div>
          </div>
        </div>
      `;
    }

    function paneTab(id, label) {
      const iconName = id === 'status' ? 'activity' : (id === 'builds' ? 'history' : 'gear');
      return `<button class="tab ${state.activePane === id ? 'active' : ''}" data-action="set-pane" data-pane="${id}">${icon(iconName)}<span>${escapeHtml(label)}</span></button>`;
    }

    function sectionTitle(iconName, label, level = 'h3') {
      return `<${level} class="section-title">${icon(iconName)}<span>${escapeHtml(label)}</span></${level}>`;
    }

    function authorLine(login, avatarURL, profileURL, suffix) {
      if (!login) return '';
      const label = `@${login}`;
      const identity = profileURL
        ? `<a href="${escapeHtmlAttr(profileURL)}" target="_blank" rel="noreferrer">${escapeHtml(label)}</a>`
        : `<span>${escapeHtml(label)}</span>`;
      return `
        <div class="avatar-row" style="margin-top: 8px;">
          ${avatarURL ? `<span class="avatar"><img src="${escapeHtmlAttr(avatarURL)}" alt=""></span>` : '<span class="avatar"></span>'}
          ${identity}
          <span class="tiny">${escapeHtml(suffix)}</span>
        </div>
      `;
    }

    function renderGlobalForm() {
      const snapshot = state.snapshot;
      const config = state.draftConfig;
      if (!snapshot || !config) {
        return '';
      }

      const identities = snapshot.global.availableSigningIdentities;
      const identitySummary = identities.length
        ? identities.map(identity => `<span class="badge ${identity.isRecommendedForSparkle ? 'success' : ''}">${escapeHtml(identity.displayName)}</span>`).join('')
        : '<span class="tiny">No signing identities detected.</span>';
      const profileOptions = snapshot.global.availableNotarizationProfiles.length
        ? snapshot.global.availableNotarizationProfiles.map(profile => `<span class="badge">${escapeHtml(profile)}</span>`).join('')
        : '<span class="tiny">No notarization profiles stored yet.</span>';

      const tabs = [
        settingsTabButton('general', 'sliders', 'General'),
        settingsTabButton('automation', 'activity', 'Automation'),
        settingsTabButton('account', 'user', 'Account'),
        settingsTabButton('signing', 'shield', 'Signing'),
        settingsTabButton('files', 'folder', 'Files')
      ].join('');

      const panes = {
        general: `
          <div class="settings-pane-grid">
            <div class="settings-card">
              ${sectionTitle('sliders', 'General', 'h2')}
              <div class="field-grid">
                ${textInput('Poll Interval (Seconds)', 'global.pollIntervalSeconds', config.pollIntervalSeconds, 'number')}
                ${textInput('GitHub Token Env Var', 'global.githubTokenEnvVar', config.githubTokenEnvVar)}
                ${textInput('Builds To Keep', 'global.generatedDataRetentionCount', config.generatedDataRetentionCount, 'number')}
                ${textInput('Auto Pause After Fails', 'global.autoPauseFailureCount', config.autoPauseFailureCount, 'number')}
                ${textInput('GitHub Token', 'global.githubToken', config.githubToken, 'password')}
              </div>
              <p class="settings-note">GitHub token is optional for public repositories, recommended for rate limits, and required for private repositories. ShipHook stores the configured token in your local config file.</p>
              <div class="toolbar">
                <button class="button primary" data-action="save">${icon('save')}<span>Save Configuration</span></button>
                <button class="button" data-action="reload">${icon('refresh')}<span>Reload From Disk</span></button>
              </div>
            </div>
            <div class="settings-stack">
              <div class="settings-card">
                ${sectionTitle('overview', 'Config File')}
                <div class="summary-list">
                  <div class="summary-row">
                    <div class="summary-row-label">Location</div>
                    <div class="summary-row-value">${escapeHtml(snapshot.global.configPath || 'Unknown')}</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        `,
        account: renderAccountSecurityPane(),
        automation: `
          <div class="settings-pane-grid">
            <div class="settings-card">
              ${sectionTitle('activity', 'Automation', 'h2')}
              <div class="field-grid single">
                <label class="field toggle">
                  <input type="checkbox" ${snapshot.global.launchesAtLogin ? 'checked' : ''} data-launch-toggle>
                  <span>Launch ShipHook at login</span>
                </label>
                <label class="field toggle">
                  <input type="checkbox" data-field="global.webDashboardEnabled" ${config.webDashboardEnabled ? 'checked' : ''}>
                  <span>Serve the local web dashboard</span>
                </label>
              </div>
              <div class="field-grid" style="margin-top: 12px;">
                ${textInput('Web Dashboard Port', 'global.webDashboardPort', config.webDashboardPort, 'number')}
                ${readOnlyInput('Current URL', snapshot.global.webDashboardURLString || 'Not running')}
              </div>
              <p class="settings-note">${escapeHtml(snapshot.global.launchAtLoginStatusMessage || snapshot.global.webDashboardStatusMessage || 'Automation settings are applied locally on this Mac.')}</p>
            </div>
            <div class="settings-stack">
              <div class="settings-card">
                ${sectionTitle('globe', 'Dashboard Status')}
                <div class="summary-list">
                  <div class="summary-row">
                    <div class="summary-row-label">Local Dashboard</div>
                    <div class="summary-row-value">${escapeHtml(snapshot.global.webDashboardStatusMessage || 'Unknown')}</div>
                  </div>
                  <div class="summary-row">
                    <div class="summary-row-label">Open</div>
                    <div class="summary-row-value">${escapeHtml(snapshot.global.webDashboardURLString || 'Not running')}</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        `,
        signing: `
          <div class="settings-pane-grid">
            <div class="settings-card">
              ${sectionTitle('shield', 'Signing Readiness', 'h2')}
              <div class="summary-list">
                <div class="summary-row">
                  <div class="summary-row-label">Summary</div>
                  <div class="summary-row-value">${escapeHtml(snapshot.global.signingDiagnosticsSummary || 'Refresh identities to inspect this Mac.')}</div>
                </div>
                ${snapshot.global.lastSigningIdentityError ? `
                  <div class="summary-row">
                    <div class="summary-row-label">Last Error</div>
                    <div class="summary-row-value">${escapeHtml(snapshot.global.lastSigningIdentityError)}</div>
                  </div>
                ` : ''}
              </div>
              <div class="badges" style="margin-top: 16px;">${identitySummary}</div>
              <div class="toolbar">
                <button class="button secondary" data-action="refresh-signing">${icon('shield')}<span>Refresh Signing Identities</span></button>
              </div>
              ${snapshot.global.signingDiagnosticsDetails.length ? `<p class="settings-note">${snapshot.global.signingDiagnosticsDetails.map(escapeHtml).join('<br>')}</p>` : ''}
            </div>
            <div class="settings-stack">
              <div class="settings-card">
                ${sectionTitle('key', 'Notarization Profiles')}
                <div class="badges">${profileOptions}</div>
              </div>
              <div class="settings-card">
                ${sectionTitle('key', 'Add Profile')}
                <div class="field-grid">
                  ${textInput('Profile Name', 'notary.profileName', notarizationDraft.profileName)}
                  ${textInput('Apple ID', 'notary.appleID', notarizationDraft.appleID)}
                  ${textInput('Team ID', 'notary.teamID', notarizationDraft.teamID)}
                  ${textInput('App-Specific Password', 'notary.appSpecificPassword', notarizationDraft.appSpecificPassword, 'password')}
                </div>
                <div class="toolbar">
                  <button class="button secondary" data-action="store-profile">${icon('key')}<span>Store Profile</span></button>
                </div>
              </div>
            </div>
          </div>
        `,
        files: `
          <div class="settings-pane-grid single">
            <div class="settings-card">
              ${sectionTitle('folder', 'Files & Storage', 'h2')}
              <div class="summary-list">
                <div class="summary-row">
                  <div class="summary-row-label">Configuration</div>
                  <div class="summary-row-value">${escapeHtml(snapshot.global.configPath || 'Unknown')}</div>
                </div>
                <div class="summary-row">
                  <div class="summary-row-label">Retention</div>
                  <div class="summary-row-value">ShipHook currently keeps ${escapeHtml(String(config.generatedDataRetentionCount))} generated build artifacts per repository.</div>
                </div>
              </div>
              <p class="settings-note">This mirrors the lighter utility-style panes in Safari settings: quick context on the left, details without crowding, and the core actions kept nearby.</p>
            </div>
          </div>
        `
      };

      return `
        <div class="settings-shell">
          <div class="settings-tabs">${tabs}</div>
          ${panes[state.settingsPane] || panes.general}
        </div>
      `;
    }

    function renderAccountSecurityPane() {
      if (state.securityLoading && !state.securityState) {
        return '<div class="settings-card"><div class="empty">Loading account security...</div></div>';
      }

      const security = state.securityState;
      if (!security) {
        return `
          <div class="settings-pane-grid single">
            <div class="settings-card">
              ${sectionTitle('user', 'Account & Security', 'h2')}
              <div class="empty">Account security has not loaded yet.</div>
            </div>
          </div>
        `;
      }

      const adminRows = security.admins.map(admin => `
        <div class="security-row">
          <div class="security-row-main">
            <strong>@${escapeHtml(admin.username)}</strong>
            <span class="tiny">${admin.isCurrentUser ? 'Signed in' : (admin.mustChangePassword ? 'Password setup pending' : `Created ${formatDate(admin.createdAt)}`)}</span>
          </div>
          <div class="security-row-actions">
            <button class="button" data-action="security-reset-admin" data-username="${escapeHtmlAttr(admin.username)}">${icon('key')}<span>Reset</span></button>
            ${admin.isCurrentUser ? '' : `<button class="button warn" data-action="security-delete-admin" data-username="${escapeHtmlAttr(admin.username)}">${icon('trash')}<span>Delete</span></button>`}
          </div>
        </div>
      `).join('');

      const passkeyRows = security.passkeys.length
        ? security.passkeys.map(passkey => `
          <div class="security-row compact">
            <div class="security-row-main">
              <strong>${escapeHtml(passkey.name || 'Passkey')}</strong>
              <span class="tiny">@${escapeHtml(passkey.username)} · ${escapeHtml(formatDate(passkey.addedAt))}</span>
            </div>
          </div>
        `).join('')
        : '<div class="empty">No passkeys registered yet.</div>';

      const auditRows = security.auditEntries.length
        ? security.auditEntries.map(entry => `
          <div class="audit-row">
            <div class="audit-icon">${icon(auditIcon(entry.action))}</div>
            <div class="audit-copy">
              <div class="audit-line">
                <strong>${escapeHtml(formatAuditAction(entry.action))}</strong>
                <span class="tiny">${escapeHtml(formatDate(entry.occurredAt))}</span>
              </div>
              <div class="tiny">${entry.username ? '@' + escapeHtml(entry.username) : 'Unknown user'}${entry.detail ? ' / ' + escapeHtml(entry.detail) : ''}${entry.remoteAddress ? ' / ' + escapeHtml(entry.remoteAddress) : ''}</div>
            </div>
          </div>
        `).join('')
        : '<div class="empty">No audit entries recorded yet.</div>';

      const inviteLink = state.securityInviteLink
        ? `<div class="invite-card"><strong>@${escapeHtml(state.securityInviteLink.username)}</strong><span class="tiny">${escapeHtml(state.securityInviteLink.label)}</span><a href="${escapeHtmlAttr(state.securityInviteLink.url)}">${escapeHtml(state.securityInviteLink.url)}</a></div>`
        : '';

      return `
        <div class="settings-pane-grid">
          <div class="settings-stack">
            <div class="settings-card">
              ${sectionTitle('user', 'Account & Security', 'h2')}
              <div class="summary-list">
                <div class="summary-row">
                  <div class="summary-row-label">Signed In</div>
                  <div class="summary-row-value">@${escapeHtml(security.currentUsername || 'Unknown')}</div>
                </div>
              </div>
              <div class="field-grid" style="margin-top: 14px;">
                ${textInput('Current Password', 'security.currentPassword', securityDraft.currentPassword, 'password')}
                ${textInput('New Password', 'security.newPassword', securityDraft.newPassword, 'password')}
              </div>
              <div class="toolbar">
                <button class="button primary" data-action="security-change-password">${icon('save')}<span>Change Password</span></button>
                <button class="button" data-action="security-register-passkey">${icon('key')}<span>Add Passkey</span></button>
              </div>
              ${state.securityStatus ? `<p class="settings-note">${escapeHtml(state.securityStatus)}</p>` : ''}
            </div>
            <div class="settings-card">
              ${sectionTitle('repo', 'Administrators')}
              <div class="security-list">${adminRows || '<div class="empty">No administrators configured.</div>'}</div>
              <div class="field-grid single" style="margin-top: 14px;">
                ${textInput('New Administrator Username', 'security.inviteUsername', securityDraft.inviteUsername)}
              </div>
              <div class="toolbar">
                <button class="button secondary" data-action="security-invite-admin">${icon('plus')}<span>Add Administrator</span></button>
              </div>
              ${inviteLink}
            </div>
          </div>
          <div class="settings-stack">
            <div class="settings-card">
              ${sectionTitle('key', 'Passkeys')}
              <div class="security-list">${passkeyRows}</div>
            </div>
            <div class="settings-card audit-card">
              ${sectionTitle('history', 'Audit Log')}
              <div class="audit-list">${auditRows}</div>
            </div>
          </div>
        </div>
      `;
    }

    function settingsTabButton(id, iconName, label) {
      return `<button class="settings-tab ${state.settingsPane === id ? 'active' : ''}" data-action="set-settings-pane" data-settings-pane="${id}">${icon(iconName)}<span>${escapeHtml(label)}</span></button>`;
    }

    function renderStatusPane() {
      const node = document.getElementById('pane-status');
      const repo = selectedRepoSnapshot();
      if (!repo) {
        node.innerHTML = '<div class="empty">Select a repository to inspect runtime state.</div>';
        return;
      }

      const progress = repo.progress ? `
        <div class="progress"><span style="width:${Math.max(4, repo.progress.fractionComplete * 100)}%"></span></div>
        <div class="tiny" style="margin-top:8px;">Step ${repo.progress.currentStep} of ${repo.progress.totalSteps}: ${escapeHtml(repo.progress.label)}</div>
      ` : '';
      const statusLabel = repo.configuration.isEnabled ? repo.runtime.activity : 'paused';
      const statusTitleLabel = repo.configuration.isEnabled ? statusLabel : 'idle';
      const statusBadge = badge(
        repo.configuration.isEnabled ? 'activity' : 'pause',
        statusLabel,
        activityTone(statusLabel)
      );
      const channelText = repo.runtime.releaseChannel === 'beta' ? 'Channel: Beta' : 'Channel: Stable';

      node.innerHTML = `
        <section class="panel">
          <div class="status-card-head">
            <div></div>
            ${statusBadge}
          </div>
          <strong class="status-title">${icon(repo.configuration.isEnabled ? 'activity' : 'pause')}<span>${escapeHtml(statusTitleLabel.charAt(0).toUpperCase() + statusTitleLabel.slice(1))}</span></strong>
          <p>${escapeHtml(repo.runtime.summary)}</p>
          ${authorLine(repo.runtime.lastCommitAuthorLogin, repo.runtime.lastCommitAuthorAvatarURL, repo.runtime.lastCommitAuthorProfileURL, 'published this commit')}
          <p>Current version: ${escapeHtml(repo.version || 'Unknown')}</p>
          <p>${escapeHtml(channelText)}</p>
          <p>Published version: ${escapeHtml(repo.publishedVersion || 'None')}</p>
          ${progress}
          ${repo.runtime.lastError ? `<p>${escapeHtml(repo.runtime.lastError)}</p>` : ''}
          <div class="row tiny" style="margin-top: 10px;">
            ${repo.runtime.buildStartedAt ? `<span>${escapeHtml(formatDate(repo.runtime.buildStartedAt))}</span>` : ''}
            ${repo.runtime.lastLogPath ? `<span class="mono">${escapeHtml(repo.runtime.lastLogPath)}</span>` : ''}
          </div>
        </section>
        <section class="panel">
          ${sectionTitle('terminal', 'Live Output', 'h2')}
          ${repo.runtime.lastLog ? `<div class="log-panel">${escapeHtml(repo.runtime.lastLog)}</div>` : '<div class="empty">No output yet.</div>'}
          ${repo.runtime.lastLogPath ? `<div class="tiny mono" style="margin-top: 10px;">${escapeHtml(repo.runtime.lastLogPath)}</div>` : ''}
        </section>
      `;
    }

    function renderBuildsPane() {
      const node = document.getElementById('pane-builds');
      const draft = selectedRepoDraft();
      const repo = selectedRepoSnapshot();
      if (!draft || !repo) {
        node.innerHTML = '<section class="panel"><div class="empty">Add or select a repository to inspect its details.</div></section>';
        return;
      }

      const releaseOptions = repo.recentReleases.map(release => `
        <div class="item">
          <div class="row" style="justify-content: space-between;">
            <h4>${escapeHtml(release.name || release.tagName)}</h4>
            <button class="button ${release.isPrerelease ? '' : 'secondary'}" data-action="rollback" data-repo-id="${repo.id}" data-tag-name="${escapeHtmlAttr(release.tagName)}">Rollback</button>
          </div>
          <div class="tiny">${escapeHtml(release.tagName)} · ${escapeHtml(formatDate(release.publishedAt) || 'Unknown date')}</div>
          <p>${escapeHtml((release.body || '').trim().slice(0, 240) || 'No release notes.')}</p>
        </div>
      `).join('');

      const buildItems = repo.recentBuilds.map(build => `
        <div class="item">
          <h4>${escapeHtml(build.version)}</h4>
          <div class="tiny">${escapeHtml(shortSha(build.sha))} · ${escapeHtml(formatDate(build.builtAt))}</div>
          <p>${escapeHtml(build.summary || 'No summary')}</p>
          ${build.logPath ? `<p class="tiny mono">${escapeHtml(build.logPath)}</p>` : ''}
        </div>
      `).join('');
      const previewBuilds = repo.recentBuilds.slice(0, 2);
      const previewReleases = repo.recentReleases.slice(0, 2);
      const buildPreviewItems = previewBuilds.map(build => `
        <div class="item">
          <h4>${escapeHtml(build.version)}</h4>
          <div class="tiny">${escapeHtml(shortSha(build.sha))} · ${escapeHtml(formatDate(build.builtAt))}</div>
          <p>${escapeHtml(build.summary || 'No summary')}</p>
          ${authorLine(build.authorLogin, build.authorAvatarURL, build.authorProfileURL, 'built this release')}
        </div>
      `).join('');
      const releasePreviewItems = previewReleases.map(release => `
        <div class="item">
          <h4>${escapeHtml(release.tagName)}</h4>
          <div class="tiny">${escapeHtml(release.isPrerelease ? 'Beta' : 'Stable')} · ${escapeHtml(formatDate(release.publishedAt) || 'Unknown date')}</div>
          <p>${escapeHtml(release.name || 'No release title')}</p>
          ${authorLine(release.authorLogin, release.authorAvatarURL, release.authorProfileURL, 'published this release')}
        </div>
      `).join('');

      node.innerHTML = `
        <section class="panel">
          <div class="editor">
            <section class="editor-section">
              ${sectionTitle('history', 'Build History')}
              <div class="collection">${buildPreviewItems || '<div class="empty">No builds recorded yet.</div>'}</div>
              ${repo.recentBuilds.length > 2 ? `<div class="tiny" style="margin-top: 10px;">${repo.recentBuilds.length - 2} more build${repo.recentBuilds.length - 2 === 1 ? '' : 's'}.</div>` : ''}
              ${repo.recentBuilds.length ? `<div class="toolbar"><button class="button" type="button" data-action="open-explorer" data-explorer="builds">${icon('overview')}<span>Explore Builds</span></button></div>` : ''}
            </section>
            <section class="editor-section">
              ${sectionTitle('releases', 'Release Explorer')}
              <div class="collection">${releasePreviewItems || '<div class="empty">No releases loaded yet.</div>'}</div>
              ${repo.recentReleases.length > 2 ? `<div class="tiny" style="margin-top: 10px;">${repo.recentReleases.length - 2} more release${repo.recentReleases.length - 2 === 1 ? '' : 's'}.</div>` : ''}
              ${repo.recentReleases.length ? `<div class="toolbar"><button class="button" type="button" data-action="open-explorer" data-explorer="releases">${icon('overview')}<span>Explore Releases</span></button></div>` : ''}
            </section>
          </div>
        </section>
      `;
    }

    function renderConfigurationPane() {
      const node = document.getElementById('pane-configuration');
      const draft = selectedRepoDraft();
      const repo = selectedRepoSnapshot();
      if (!draft || !repo) {
        node.innerHTML = `
          <section class="panel">
            <div class="empty">Select a repository to edit its configuration. Use the gear button in the header for ShipHook settings.</div>
          </section>
        `;
        return;
      }

      const repoSummary = summaryList([
        ['Repository', `${draft.owner || 'Unknown'}/${draft.repo || 'Unknown'}`],
        ['Branch', draft.branch || 'main'],
        ['Checkout', draft.localCheckoutPath || 'Not set']
      ]);

      const buildSummary = draft.buildMode === 'shell'
        ? summaryList([
          ['Build Command', draft.shell.command || 'Not set'],
          ['Artifact Path', draft.shell.artifactPath || 'Not set']
        ])
        : summaryList([
          ['Scheme', draft.xcode.scheme || 'Not set'],
          ['App Name', draft.xcode.appName || 'Not set'],
          ['Configuration', draft.xcode.configuration || 'Release']
        ]);

      const sparkleSummary = summaryList([
        ['Appcast', draft.sparkle.appcastURL || 'Not set'],
        ['Skip Older Versions', draft.sparkle.skipIfVersionIsNotNewer ? 'Enabled' : 'Disabled'],
        ['Auto Increment Build', draft.sparkle.autoIncrementBuild ? 'Enabled' : 'Disabled'],
        ['Existing Release Notes', draft.preferExistingReleaseNotesFile ? 'Prefer Existing File' : 'Generate From Commits']
      ]);

      const webhookSummary = summaryList([
        ['Success Notifications', draft.notifications.postOnSuccess ? 'Enabled' : 'Disabled'],
        ['Failure Notifications', draft.notifications.postOnFailure ? 'Enabled' : 'Disabled'],
        ['Webhook URL', draft.notifications.discordWebhookURL || 'Not set']
      ]);

      node.innerHTML = `
        <section class="panel">
          <div class="editor">
            <section class="editor-section">
              <div class="section-header">
                ${sectionTitle('repo', 'Repository Setup')}
                ${sectionToggle('repoSetup', state.configSections.repoSetup)}
              </div>
              ${state.configSections.repoSetup ? `
                <div class="field-grid">
                  ${textInput('Display Name', 'repo.name', draft.name)}
                  ${readOnlyInput('Repository ID', draft.id)}
                  ${textInput('GitHub Owner', 'repo.owner', draft.owner)}
                  ${textInput('Repository', 'repo.repo', draft.repo)}
                  ${textInput('Branch', 'repo.branch', draft.branch)}
                  ${textInput('Working Directory', 'repo.workingDirectory', draft.workingDirectory)}
                  ${textInput('Local Checkout Path', 'repo.localCheckoutPath', draft.localCheckoutPath)}
                  ${selectInput('Build Mode', 'repo.buildMode', draft.buildMode, [
                    ['xcodeArchive', 'Xcode Archive'],
                    ['shell', 'Shell']
                  ])}
                  ${selectInput('Version Strategy', 'repo.versionStrategy', draft.versionStrategy, [
                    ['shortSHA', 'Short SHA'],
                    ['shortSHATimestamp', 'Short SHA + Timestamp'],
                    ['dateAndShortSHA', 'Date + Short SHA']
                  ])}
                  ${textInput('Repo Token Env Var', 'repo.githubTokenEnvVar', draft.githubTokenEnvVar)}
                  ${textInput('Release Notes Path', 'repo.releaseNotesPath', draft.releaseNotesPath)}
                </div>
                <div class="field-grid" style="margin-top: 12px;">
                  ${toggleInput('Repository Enabled', 'repo.isEnabled', draft.isEnabled)}
                  ${toggleInput('Build On First Seen Commit', 'repo.buildOnFirstSeen', draft.buildOnFirstSeen)}
                </div>
              ` : repoSummary}
            </section>
            <section class="editor-section">
              <div class="section-header">
                ${sectionTitle('hammer', 'Build Automation')}
                ${sectionToggle('buildAutomation', state.configSections.buildAutomation)}
              </div>
              ${state.configSections.buildAutomation ? `
                <div class="field-grid">
                  ${textInput('Workspace Path', 'repo.xcode.workspacePath', draft.xcode.workspacePath)}
                  ${textInput('Project Path', 'repo.xcode.projectPath', draft.xcode.projectPath)}
                  ${textInput('Scheme', 'repo.xcode.scheme', draft.xcode.scheme)}
                  ${textInput('App Name', 'repo.xcode.appName', draft.xcode.appName)}
                  ${textInput('Configuration', 'repo.xcode.configuration', draft.xcode.configuration)}
                  ${textInput('Archive Path', 'repo.xcode.archivePath', draft.xcode.archivePath)}
                  ${textInput('Artifact Path', 'repo.xcode.artifactPath', draft.xcode.artifactPath)}
                  ${textInput('Shell Artifact Path', 'repo.shell.artifactPath', draft.shell.artifactPath)}
                </div>
                <div class="field-grid single" style="margin-top: 12px;">
                  ${textAreaInput('Shell Command', 'repo.shell.command', draft.shell.command, 6)}
                </div>
              ` : buildSummary}
            </section>
            <section class="editor-section">
              <div class="section-header">
                ${sectionTitle('sparkles', 'Sparkle')}
                ${sectionToggle('sparkle', state.configSections.sparkle)}
              </div>
              ${state.configSections.sparkle ? `
                <div class="field-grid">
                  ${textInput('Appcast URL', 'repo.sparkle.appcastURL', draft.sparkle.appcastURL)}
                  ${textInput('Beta Icon Path', 'repo.sparkle.betaIconPath', draft.sparkle.betaIconPath)}
                  ${toggleInput('Auto Increment Build', 'repo.sparkle.autoIncrementBuild', draft.sparkle.autoIncrementBuild)}
                  ${toggleInput('Skip If Version Not Newer', 'repo.sparkle.skipIfVersionIsNotNewer', draft.sparkle.skipIfVersionIsNotNewer)}
                  ${toggleInput('Prefer Existing Versioned Release Notes File', 'repo.preferExistingReleaseNotesFile', draft.preferExistingReleaseNotesFile)}
                </div>
              ` : sparkleSummary}
            </section>
            <section class="editor-section">
              ${sectionTitle('shield', 'Signing')}
              <div class="field-grid">
                ${textInput('Development Team', 'repo.signing.developmentTeam', draft.signing.developmentTeam)}
                ${selectInput('Code Sign Style', 'repo.signing.codeSignStyle', draft.signing.codeSignStyle, [
                  ['automatic', 'Automatic'],
                  ['manual', 'Manual']
                ])}
                ${textInput('Signing Identity', 'repo.signing.codeSignIdentity', draft.signing.codeSignIdentity)}
                ${textInput('Notarization Profile', 'repo.signing.notarizationProfile', draft.signing.notarizationProfile)}
              </div>
            </section>
            <section class="editor-section">
              <div class="section-header">
                ${sectionTitle('webhook', 'Webhooks')}
                ${sectionToggle('webhooks', state.configSections.webhooks)}
              </div>
              ${state.configSections.webhooks ? `
                <div class="field-grid">
                  ${textInput('Discord Webhook URL', 'repo.notifications.discordWebhookURL', draft.notifications.discordWebhookURL)}
                  ${toggleInput('Post On Success', 'repo.notifications.postOnSuccess', draft.notifications.postOnSuccess)}
                  ${toggleInput('Post On Failure', 'repo.notifications.postOnFailure', draft.notifications.postOnFailure)}
                </div>
              ` : webhookSummary}
            </section>
            <section class="editor-section">
              <div class="section-header">
                ${sectionTitle('sliders', 'Advanced Build Settings')}
                ${sectionToggle('advanced', state.configSections.advanced)}
              </div>
              ${state.configSections.advanced ? `
                <div class="field-grid single">
                  ${textAreaInput('Publish Command', 'repo.publishCommand', draft.publishCommand, 6)}
                  ${textAreaInput('Environment (JSON object)', 'repo.environment', JSON.stringify(draft.environment, null, 2), 6)}
                </div>
              ` : '<div class="tiny">Project overrides, publish command, and environment live here when needed.</div>'}
            </section>
            <section class="editor-section">
              <div class="toolbar">
                <button class="button warn" data-action="remove-repo" data-repo-id="${repo.id}">${icon('trash')}<span>Delete Repository</span></button>
              </div>
            </section>
          </div>
        </section>
      `;
    }

    function selectedRepoSnapshot() {
      return state.snapshot?.repositories.find(repo => repo.id === state.selectedRepoId) || null;
    }

    function selectedRepoDraft() {
      return state.draftConfig?.repositories.find(repo => repo.id === state.selectedRepoId) || null;
    }

    function summaryPill(iconName, label, detail) {
      const trailing = detail
        ? `<span class="divider">/</span><span class="muted">${escapeHtml(detail)}</span>`
        : '';
      return `<div class="summary-pill">${icon(iconName)}<span>${escapeHtml(label)}</span>${trailing}</div>`;
    }

    function repoStatusBadge(repo) {
      const status = repo.configuration.isEnabled ? repo.runtime.activity : 'paused';
      const iconName = repo.configuration.isEnabled ? 'activity' : 'pause';
      return `<span class="badge icon-only ${activityTone(status)}" title="${escapeHtmlAttr(status)}" aria-label="${escapeHtmlAttr(status)}">${icon(iconName)}<span>${escapeHtml(status)}</span></span>`;
    }

    function badge(iconName, text, tone = '') {
      return `<span class="badge ${tone}">${icon(iconName)}<span>${escapeHtml(text)}</span></span>`;
    }

    function sectionToggle(section, isOpen) {
      return `<button class="button section-toggle" data-action="toggle-config-section" data-section="${section}"><span>${isOpen ? 'Done' : 'Configure'}</span></button>`;
    }

    function summaryList(rows) {
      return `
        <div class="summary-list">
          ${rows.map(([label, value]) => `
            <div class="summary-row">
              <div class="summary-row-label">${escapeHtml(label)}</div>
              <div class="summary-row-value">${escapeHtml(value || 'Not set')}</div>
            </div>
          `).join('')}
        </div>
      `;
    }

    function textInput(label, path, value, type = 'text') {
      return `<label class="field">${escapeHtml(label)}<input type="${type}" value="${escapeHtmlAttr(value ?? '')}" data-field="${path}"></label>`;
    }

    function textAreaInput(label, path, value, rows = 6) {
      return `<label class="field">${escapeHtml(label)}<textarea rows="${rows}" data-field="${path}">${escapeHtml(value ?? '')}</textarea></label>`;
    }

    function readOnlyInput(label, value) {
      return `<label class="field">${escapeHtml(label)}<input type="text" value="${escapeHtmlAttr(value ?? '')}" readonly class="dim"></label>`;
    }

    function selectInput(label, path, value, options) {
      return `
        <label class="field">${escapeHtml(label)}
          <select data-field="${path}">
            ${options.map(([optionValue, optionLabel]) => `<option value="${escapeHtmlAttr(optionValue)}" ${optionValue === value ? 'selected' : ''}>${escapeHtml(optionLabel)}</option>`).join('')}
          </select>
        </label>
      `;
    }

    function toggleInput(label, path, checked) {
      return `<label class="field toggle"><input type="checkbox" data-field="${path}" ${checked ? 'checked' : ''}><span>${escapeHtml(label)}</span></label>`;
    }

    function icon(name) {
      const icons = {
        overview: '<svg viewBox="0 0 24 24"><path d="M4 5h7v6H4z"/><path d="M13 5h7v10h-7z"/><path d="M4 13h7v6H4z"/><path d="M13 17h7v2h-7z"/></svg>',
        repos: '<svg viewBox="0 0 24 24"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4H20v16H6.5A2.5 2.5 0 0 0 4 22z"/><path d="M8 8h8"/><path d="M8 12h8"/></svg>',
        repo: '<svg viewBox="0 0 24 24"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4H20v16H6.5A2.5 2.5 0 0 0 4 22z"/><path d="M8 8h8"/><path d="M8 12h8"/></svg>',
        'repo-refresh': '<svg viewBox="0 0 24 24"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4H20v16H6.5A2.5 2.5 0 0 0 4 22z"/><path d="M8 8h6"/><path d="M8 12h5"/><path d="M16 9a3.5 3.5 0 1 1-1 6.86"/><path d="M16 7v2h-2"/></svg>',
        settings: '<svg viewBox="0 0 24 24"><path d="M12 3v4"/><path d="M12 17v4"/><path d="M3 12h4"/><path d="M17 12h4"/><circle cx="12" cy="12" r="4"/></svg>',
        user: '<svg viewBox="0 0 24 24"><path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z"/><path d="M4 20a8 8 0 0 1 16 0"/></svg>',
        gear: '<svg viewBox="0 0 24 24"><path d="M10.55 2.52h2.9l.43 2.14a7.92 7.92 0 0 1 1.72.71l1.87-1.14 2.05 2.05-1.14 1.87c.29.55.53 1.13.71 1.72l2.14.43v2.9l-2.14.43a7.92 7.92 0 0 1-.71 1.72l1.14 1.87-2.05 2.05-1.87-1.14a7.92 7.92 0 0 1-1.72.71l-.43 2.14h-2.9l-.43-2.14a7.92 7.92 0 0 1-1.72-.71l-1.87 1.14-2.05-2.05 1.14-1.87a7.92 7.92 0 0 1-.71-1.72L2.52 13.45v-2.9l2.14-.43c.18-.59.42-1.17.71-1.72L4.23 6.53l2.05-2.05 1.87 1.14c.55-.29 1.13-.53 1.72-.71zm1.45 6.23a3.25 3.25 0 1 0 0 6.5 3.25 3.25 0 0 0 0-6.5Z"/></svg>',
        refresh: '<svg viewBox="0 0 24 24"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/></svg>',
        save: '<svg viewBox="0 0 24 24"><path d="M5 4h11l3 3v13H5z"/><path d="M8 4v6h8V4"/><path d="M9 18h6"/></svg>',
        play: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="m10 8 6 4-6 4z"/></svg>',
        pause: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M10 9v6"/><path d="M14 9v6"/></svg>',
        activity: '<svg viewBox="0 0 24 24"><path d="M4 12h4l2-4 4 8 2-4h4"/></svg>',
        globe: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 0 1 0 18"/><path d="M12 3a15 15 0 0 0 0 18"/></svg>',
        shield: '<svg viewBox="0 0 24 24"><path d="M12 3 5 6v6c0 4.5 2.9 7.9 7 9 4.1-1.1 7-4.5 7-9V6z"/></svg>',
        key: '<svg viewBox="0 0 24 24"><circle cx="8.5" cy="15.5" r="3.5"/><path d="M12 15.5h8"/><path d="M17 12.5v3"/><path d="M20 13.5v2"/></svg>',
        sparkles: '<svg viewBox="0 0 24 24"><path d="m12 3 1.4 4.6L18 9l-4.6 1.4L12 15l-1.4-4.6L6 9l4.6-1.4z"/><path d="m19 15 .8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/></svg>',
        history: '<svg viewBox="0 0 24 24"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v5l3 2"/></svg>',
        terminal: '<svg viewBox="0 0 24 24"><path d="m5 7 4 5-4 5"/><path d="M12 17h7"/><rect x="3" y="4" width="18" height="16" rx="2"/></svg>',
        releases: '<svg viewBox="0 0 24 24"><path d="M6 8h12"/><path d="M6 12h12"/><path d="M6 16h8"/><path d="M4 5h16v14H4z"/></svg>',
        folder: '<svg viewBox="0 0 24 24"><path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H10l2 2h6.5A2.5 2.5 0 0 1 21 9.5v8A2.5 2.5 0 0 1 18.5 20h-13A2.5 2.5 0 0 1 3 17.5z"/></svg>',
        webhook: '<svg viewBox="0 0 24 24"><path d="M8 12a4 4 0 1 1 4 4"/><path d="M16 12a4 4 0 1 0-4 4"/><circle cx="8" cy="12" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="12" cy="16" r="2"/></svg>',
        hammer: '<svg viewBox="0 0 24 24"><path d="m14 6 4 4"/><path d="m11 9 4-4 4 4-4 4"/><path d="M5 21 13 13"/><path d="m4 20 2 2"/></svg>',
        sliders: '<svg viewBox="0 0 24 24"><path d="M4 6h16"/><path d="M4 12h16"/><path d="M4 18h16"/><circle cx="9" cy="6" r="2"/><circle cx="15" cy="12" r="2"/><circle cx="11" cy="18" r="2"/></svg>',
        trash: '<svg viewBox="0 0 24 24"><path d="M4 7h16"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M6 7l1 13h10l1-13"/><path d="M9 7V4h6v3"/></svg>',
        plus: '<svg viewBox="0 0 24 24"><path d="M12 5v14"/><path d="M5 12h14"/></svg>',
        search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="6"/><path d="m20 20-4.2-4.2"/></svg>',
        close: '<svg viewBox="0 0 24 24"><path d="M6 6 18 18"/><path d="M18 6 6 18"/></svg>'
      };
      return `<span class="icon">${icons[name] || icons.overview}</span>`;
    }

    function activityTone(activity) {
      switch (activity) {
        case 'succeeded': return 'success';
        case 'failed': return 'danger';
        case 'building': return 'live';
        case 'polling': return 'warning';
        case 'paused': return 'warning';
        default: return '';
      }
    }

    function scheduleToastDismiss() {
      if (state.toastTimerId) {
        window.clearTimeout(state.toastTimerId);
        state.toastTimerId = null;
      }

      if (!state.toasts.length) {
        return;
      }

      state.toastTimerId = window.setTimeout(() => {
        const nextToast = state.toasts.find(toast => !toast.hovered);
        if (!nextToast) {
          scheduleToastDismiss();
          return;
        }
        state.toasts = state.toasts.filter(toast => toast.id !== nextToast.id);
        renderStatus();
        scheduleToastDismiss();
      }, 3200);
    }

    function shortSha(value) {
      return value ? String(value).slice(0, 7) : '';
    }

    function formatDate(value) {
      if (!value) return '';
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return String(value);
      return new Intl.DateTimeFormat(undefined, {
        dateStyle: 'medium',
        timeStyle: 'short'
      }).format(date);
    }

    function escapeHtml(value) {
      return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    }

    function escapeHtmlAttr(value) {
      return escapeHtml(value).replaceAll("'", '&#39;');
    }

    function parseEnvironment(text) {
      const raw = (text || '').trim();
      if (!raw) return {};
      const parsed = JSON.parse(raw);
      if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') {
        throw new Error('Environment must be a JSON object.');
      }
      const output = {};
      for (const [key, value] of Object.entries(parsed)) {
        output[String(key)] = String(value ?? '');
      }
      return output;
    }

    function coerceNumber(value, fallback) {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : fallback;
    }

    async function securityRequest(url, payload, successMessage) {
      state.securityStatus = '';
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      if (response.status === 401) {
        window.location.href = '/';
        return null;
      }
      const result = await response.json();
      if (!response.ok || result.ok === false) {
        throw new Error(result.error || 'Security request failed.');
      }
      state.securityStatus = result.message || successMessage || 'Updated.';
      await fetchSecurityState();
      renderModal();
      return result;
    }

    async function inviteAdminFromSettings() {
      const result = await securityRequest('/api/auth/admins/invite', {
        username: securityDraft.inviteUsername
      }, 'Administrator invite created.');
      if (result?.loginURL) {
        state.securityInviteLink = {
          username: result.username,
          url: result.loginURL,
          label: 'Password setup link'
        };
      }
      securityDraft.inviteUsername = '';
      renderModal();
    }

    async function resetAdminFromSettings(username) {
      const result = await securityRequest('/api/auth/admins/reset', { username }, 'Password reset link created.');
      if (result?.loginURL) {
        state.securityInviteLink = {
          username: result.username,
          url: result.loginURL,
          label: 'Password reset link'
        };
      }
      renderModal();
    }

    async function registerPasskeyFromDashboard() {
      if (!window.PublicKeyCredential || !navigator.credentials?.create) {
        throw new Error('This browser does not support passkey creation.');
      }
      state.securityStatus = '';
      const beginResponse = await fetch('/api/auth/passkeys/register/begin', { method: 'POST' });
      if (beginResponse.status === 401) {
        window.location.href = '/';
        return;
      }
      const beginPayload = await beginResponse.json();
      if (!beginResponse.ok || beginPayload.ok === false) {
        throw new Error(beginPayload.error || 'Passkey setup failed.');
      }
      const credential = await navigator.credentials.create({
        publicKey: {
          challenge: base64URLToBuffer(beginPayload.challenge),
          rp: { id: beginPayload.rpID, name: beginPayload.rpName },
          user: {
            id: base64URLToBuffer(beginPayload.userID),
            name: beginPayload.userName,
            displayName: beginPayload.userDisplayName
          },
          pubKeyCredParams: [{ type: 'public-key', alg: -7 }],
          timeout: beginPayload.timeoutMilliseconds,
          attestation: 'none',
          authenticatorSelection: {
            residentKey: 'preferred',
            userVerification: 'required'
          },
          excludeCredentials: beginPayload.excludeCredentialIDs.map(id => ({ id: base64URLToBuffer(id), type: 'public-key' }))
        }
      });
      const finishResponse = await fetch('/api/auth/passkeys/register/finish', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          challengeID: beginPayload.challengeID,
          name: '',
          credentialID: bufferToBase64URL(credential.rawId),
          clientDataJSON: bufferToBase64URL(credential.response.clientDataJSON),
          attestationObject: bufferToBase64URL(credential.response.attestationObject)
        })
      });
      const finishPayload = await finishResponse.json();
      if (!finishResponse.ok || finishPayload.ok === false) {
        throw new Error(finishPayload.error || 'Passkey setup failed.');
      }
      state.securityStatus = finishPayload.message || 'Passkey added.';
      await fetchSecurityState();
      renderModal();
    }

    function formatAuditAction(action) {
      return String(action || '')
        .split('.')
        .filter(Boolean)
        .map(part => part.replaceAll('_', ' '))
        .map(part => part.charAt(0).toUpperCase() + part.slice(1))
        .join(' / ');
    }

    function auditIcon(action) {
      if (action.includes('passkey') || action.includes('password')) return 'key';
      if (action.includes('admin')) return 'user';
      if (action.includes('reclone') || action.includes('repository')) return 'repo';
      if (action.includes('release')) return 'releases';
      if (action.includes('poll')) return 'refresh';
      if (action.includes('signing')) return 'shield';
      return 'history';
    }

    function base64URLToBuffer(value) {
      const base64 = value.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((value.length + 3) % 4);
      const binary = atob(base64);
      return Uint8Array.from(binary, char => char.charCodeAt(0));
    }

    function bufferToBase64URL(buffer) {
      const bytes = new Uint8Array(buffer);
      let binary = '';
      bytes.forEach(byte => binary += String.fromCharCode(byte));
      return btoa(binary).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/g, '');
    }

    function buildPayloadConfig() {
      const config = structuredClone(state.draftConfig);
      config.pollIntervalSeconds = coerceNumber(config.pollIntervalSeconds, globalDefaults.pollIntervalSeconds);
      config.generatedDataRetentionCount = Math.max(1, Math.round(coerceNumber(config.generatedDataRetentionCount, globalDefaults.generatedDataRetentionCount)));
      config.autoPauseFailureCount = Math.max(1, Math.round(coerceNumber(config.autoPauseFailureCount, globalDefaults.autoPauseFailureCount)));
      config.webDashboardPort = Math.round(coerceNumber(config.webDashboardPort, globalDefaults.webDashboardPort));
      config.repositories = config.repositories.map(repository => {
        const next = normalizeRepository(repository);
        next.workingDirectory = next.workingDirectory || null;
        next.releaseNotesPath = next.releaseNotesPath || null;
        next.githubTokenEnvVar = next.githubTokenEnvVar || null;
        next.xcode.projectPath = next.xcode.projectPath || null;
        next.xcode.workspacePath = next.xcode.workspacePath || null;
        next.sparkle.appcastURL = next.sparkle.appcastURL || null;
        next.sparkle.betaIconPath = next.sparkle.betaIconPath || null;
        next.notifications.discordWebhookURL = next.notifications.discordWebhookURL || null;
        next.signing.developmentTeam = next.signing.developmentTeam || null;
        next.signing.codeSignIdentity = next.signing.codeSignIdentity || null;
        next.signing.notarizationProfile = next.signing.notarizationProfile || null;
        return next;
      });
      return config;
    }

    document.addEventListener('click', async event => {
      const target = event.target.closest('[data-action], [data-select-repo]');
      if (!target) return;
      event.preventDefault();

      const selectedRepo = target.getAttribute('data-select-repo');
      if (selectedRepo) {
        state.selectedRepoId = selectedRepo;
        state.mobileSidebarOpen = false;
        render();
        return;
      }

      const action = target.getAttribute('data-action');
      try {
        switch (action) {
          case 'set-pane':
            state.activePane = target.dataset.pane;
            render();
            break;
          case 'toggle-config-section':
            state.configSections[target.dataset.section] = !state.configSections[target.dataset.section];
            renderConfigurationPane();
            break;
          case 'open-sidebar':
            state.mobileSidebarOpen = true;
            render();
            break;
          case 'close-sidebar':
            state.mobileSidebarOpen = false;
            render();
            break;
          case 'open-settings':
            openSettingsModal();
            break;
          case 'set-settings-pane':
            state.settingsPane = target.dataset.settingsPane || 'general';
            renderModal();
            if (state.settingsPane === 'account' && !state.securityState && !state.securityLoading) {
              await fetchSecurityState();
              renderModal();
            }
            break;
          case 'close-settings':
            state.settingsModalOpen = false;
            renderModal();
            break;
          case 'open-explorer':
            openExplorerModal(target.dataset.explorer);
            break;
          case 'close-explorer':
            state.explorerModal = null;
            renderModal();
            break;
          case 'open-add-repo':
            state.addRepoWizardOpen = true;
            state.addRepoInspectionPreview = null;
            state.explorerModal = null;
            state.settingsModalOpen = false;
            renderModal();
            break;
          case 'close-add-repo':
            state.addRepoWizardOpen = false;
            state.addRepoInspectionPreview = null;
            renderModal();
            break;
          case 'inspect-repo':
            await runCommand({
              type: 'inspectRepository',
              inspectionRequest: {
                localCheckoutPath: addRepoDraft.localCheckoutPath,
                fallbackOwner: addRepoDraft.fallbackOwner,
                fallbackRepo: addRepoDraft.fallbackRepo,
                fallbackBranch: addRepoDraft.fallbackBranch
              }
            }, 'Inspection succeeded.');
            renderModal();
            break;
          case 'confirm-add-repo':
            await runCommand({
              type: 'addRepositoryFromInspection',
              inspectionSubmission: {
                localCheckoutPath: addRepoDraft.localCheckoutPath,
                fallbackOwner: addRepoDraft.fallbackOwner,
                fallbackRepo: addRepoDraft.fallbackRepo,
                fallbackBranch: addRepoDraft.fallbackBranch,
                selectedScheme: addRepoDraft.selectedScheme || null
              }
            }, 'Repository added.');
            state.addRepoWizardOpen = false;
            state.activePane = 'configuration';
            state.addRepoInspectionPreview = null;
            if (state.snapshot?.repositories?.length) {
              state.selectedRepoId = state.snapshot.repositories[state.snapshot.repositories.length - 1].id;
            }
            render();
            break;
          case 'save':
            await runCommand({ type: 'saveConfiguration', configuration: buildPayloadConfig() }, 'Configuration saved.');
            break;
          case 'reload':
            await runCommand({ type: 'reloadConfiguration' }, 'Configuration reloaded.');
            break;
          case 'poll-all':
            await runCommand({ type: 'pollAll' }, 'Polling all repositories.');
            break;
          case 'poll-repo':
            await runCommand({ type: 'pollRepository', repositoryID: target.dataset.repoId }, 'Polling repository.');
            break;
          case 'reclone-repo':
            if (window.confirm('Reclone this repository locally? ShipHook will delete the current checkout folder and clone it again.')) {
              await runCommand({ type: 'recloneRepository', repositoryID: target.dataset.repoId }, 'Repository recloned.');
            }
            break;
          case 'set-repo-enabled':
            await runCommand({
              type: 'setRepositoryEnabled',
              repositoryID: target.dataset.repoId,
              enabled: target.dataset.enabled === 'true'
            }, target.dataset.enabled === 'true' ? 'Repository resumed.' : 'Repository paused.');
            break;
          case 'reset-build':
            await runCommand({ type: 'resetBuildState', repositoryID: target.dataset.repoId }, 'Build state reset.');
            break;
          case 'refresh-releases':
            await runCommand({ type: 'refreshReleases', repositoryID: target.dataset.repoId }, 'Refreshing releases.');
            break;
          case 'remove-repo':
            if (window.confirm('Remove this repository from ShipHook?')) {
              await runCommand({ type: 'removeRepository', repositoryID: target.dataset.repoId }, 'Repository removed.');
            }
            break;
          case 'rollback':
            if (window.confirm(`Rollback to ${target.dataset.tagName}?`)) {
              await runCommand({
                type: 'rollbackRelease',
                repositoryID: target.dataset.repoId,
                tagName: target.dataset.tagName
              }, 'Rollback started.');
            }
            break;
          case 'refresh-signing':
            await runCommand({ type: 'refreshSigningIdentities' }, 'Signing identities refreshed.');
            break;
          case 'store-profile':
            await runCommand({
              type: 'storeNotarizationProfile',
              notarizationProfile: structuredClone(notarizationDraft)
            }, 'Notarization profile stored.');
            notarizationDraft.profileName = '';
            notarizationDraft.appleID = '';
            notarizationDraft.teamID = '';
            notarizationDraft.appSpecificPassword = '';
            render();
            break;
          case 'security-change-password':
            await securityRequest('/api/auth/change-password', {
              currentPassword: securityDraft.currentPassword,
              newPassword: securityDraft.newPassword
            }, 'Password updated.');
            securityDraft.currentPassword = '';
            securityDraft.newPassword = '';
            break;
          case 'security-register-passkey':
            await registerPasskeyFromDashboard();
            break;
          case 'security-invite-admin':
            await inviteAdminFromSettings();
            break;
          case 'security-reset-admin':
            await resetAdminFromSettings(target.dataset.username);
            break;
          case 'security-delete-admin':
            if (window.confirm(`Delete administrator @${target.dataset.username}?`)) {
              await securityRequest('/api/auth/admins/delete', { username: target.dataset.username }, 'Administrator removed.');
            }
            break;
        }
      } catch (error) {
        setStatus({ kind: 'error', message: error.message || String(error) });
        if (state.settingsModalOpen && state.settingsPane === 'account') {
          state.securityStatus = error.message || String(error);
          renderModal();
        }
      }
    });

    document.addEventListener('input', event => {
      const target = event.target;
      const field = target.getAttribute('data-field');
      if (!field) return;

      const value = target.type === 'checkbox' ? target.checked : target.value;

      if (field.startsWith('global.')) {
        updateByPath(state.draftConfig, field.replace('global.', ''), value);
      } else if (field.startsWith('repo.')) {
        const repo = selectedRepoDraft();
        if (!repo) return;
        if (field === 'repo.environment') {
          try {
            repo.environment = parseEnvironment(value);
            target.style.borderColor = '';
          } catch {
            target.style.borderColor = 'rgba(255,109,122,0.8)';
            return;
          }
        } else {
          updateByPath(repo, field.replace('repo.', ''), value);
        }
      } else if (field.startsWith('notary.')) {
        updateByPath(notarizationDraft, field.replace('notary.', ''), value);
      } else if (field.startsWith('addRepo.')) {
        updateByPath(addRepoDraft, field.replace('addRepo.', ''), value);
      } else if (field.startsWith('security.')) {
        updateByPath(securityDraft, field.replace('security.', ''), value);
        return;
      }

      renderOverview();
      renderRepoList();
      renderStatusPane();
      renderBuildsPane();
      renderConfigurationPane();
      renderModal();
    });

    document.addEventListener('change', async event => {
      const target = event.target;
      if (target.hasAttribute('data-launch-toggle')) {
        try {
          await runCommand({
            type: 'setLaunchAtLogin',
            enabled: !!target.checked
          }, 'Launch at login updated.');
        } catch (error) {
          setStatus({ kind: 'error', message: error.message || String(error) });
        }
      }
    });

    document.addEventListener('mouseenter', event => {
      const toast = event.target.closest('[data-toast-id]');
      if (!toast) return;
      const targetToast = state.toasts.find(item => item.id === toast.dataset.toastId);
      if (!targetToast) return;
      targetToast.hovered = true;
      scheduleToastDismiss();
    }, true);

    document.addEventListener('mouseleave', event => {
      const toast = event.target.closest('[data-toast-id]');
      if (!toast) return;
      const targetToast = state.toasts.find(item => item.id === toast.dataset.toastId);
      if (!targetToast) return;
      targetToast.hovered = false;
      scheduleToastDismiss();
    }, true);

    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) {
        runAutoRefresh().catch(() => {});
      }
    });

    function updateByPath(root, path, value) {
      const segments = path.split('.');
      let target = root;
      for (let index = 0; index < segments.length - 1; index += 1) {
        const key = segments[index];
        if (target[key] == null || typeof target[key] !== 'object') {
          target[key] = {};
        }
        target = target[key];
      }
      target[segments.at(-1)] = value;
    }

    fetchState({ preserveDraft: false }).then(() => {
      scheduleAutoRefresh();
    }).catch(error => {
      setStatus({ kind: 'error', message: error.message || String(error) });
      scheduleAutoRefresh();
    });
  </script>
</body>
</html>
"""
}

private extension JSONEncoder {
    static var webDashboard: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var webDashboard: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct WebDashboardAuthSetupRequest: Codable {
    var username: String
    var password: String
    var publicBaseURL: String?
    var sessionDurationHours: Int?
}

private struct WebDashboardPasswordLoginRequest: Codable {
    var username: String
    var password: String
}

private struct WebDashboardPasswordChangeRequest: Codable {
    var currentPassword: String
    var newPassword: String
}

private struct WebDashboardInviteAcceptanceRequest: Codable {
    var token: String
    var newPassword: String
}

private struct WebDashboardAdminInviteRequest: Codable {
    var username: String
}

private struct WebDashboardAdminResetRequest: Codable {
    var username: String
}

private struct WebDashboardAdminDeleteRequest: Codable {
    var username: String
}

private struct WebDashboardAuthMessageResponse: Codable {
    var ok: Bool
    var message: String?
    var error: String?
    var passkeysAvailable: Bool?
    var requiresPasswordChange: Bool?

    init(ok: Bool, message: String? = nil, error: String? = nil, passkeysAvailable: Bool? = nil, requiresPasswordChange: Bool? = nil) {
        self.ok = ok
        self.message = message
        self.error = error
        self.passkeysAvailable = passkeysAvailable
        self.requiresPasswordChange = requiresPasswordChange
    }
}

private struct WebDashboardAdminLinkResponse: Codable {
    var ok: Bool
    var username: String
    var loginURL: String
    var message: String
}

private struct WebDashboardPasskeyRegistrationOptionsResponse: Codable {
    var ok: Bool
    var challengeID: String
    var challenge: String
    var rpID: String
    var rpName: String
    var userID: String
    var userName: String
    var userDisplayName: String
    var excludeCredentialIDs: [String]
    var timeoutMilliseconds: Int
}

private struct WebDashboardPasskeyAuthenticationOptionsResponse: Codable {
    var ok: Bool
    var challengeID: String
    var challenge: String
    var rpID: String
    var credentialIDs: [String]
    var timeoutMilliseconds: Int
}

private struct WebDashboardFinishPasskeyRegistrationRequest: Codable {
    var challengeID: String
    var name: String?
    var credentialID: String
    var clientDataJSON: String
    var attestationObject: String
}

private struct WebDashboardFinishPasskeyAuthenticationRequest: Codable {
    var challengeID: String
    var credentialID: String
    var clientDataJSON: String
    var authenticatorData: String
    var signature: String
    var userHandle: String?
}

private final class WebDashboardSecurityController {
    private enum PasswordAlgorithm: String, Codable {
        case legacyIteratedSHA256 = "iterated-sha256"
        case pbkdf2SHA256 = "pbkdf2-sha256"
    }

    enum SecurityError: LocalizedError {
        case bootstrapUnavailable
        case invalidInput(String)
        case weakPassword
        case unauthorized
        case rateLimited
        case passkeysUnavailable(String)
        case invalidCredential

        var errorDescription: String? { userMessage }

        var userMessage: String {
            switch self {
            case .bootstrapUnavailable:
                return "Initial setup is only available from localhost."
            case let .invalidInput(message):
                return message
            case .weakPassword:
                return "Password must be at least 14 characters long."
            case .unauthorized:
                return "Authentication required."
            case .rateLimited:
                return "Too many failed attempts. Try again shortly."
            case let .passkeysUnavailable(message):
                return message
            case .invalidCredential:
                return "The supplied credential could not be verified."
            }
        }

        var statusCode: Int {
            switch self {
            case .rateLimited:
                return 429
            case .bootstrapUnavailable:
                return 403
            case .unauthorized:
                return 401
            default:
                return 400
            }
        }

        var reasonPhrase: String {
            switch self {
            case .rateLimited:
                return "Too Many Requests"
            case .bootstrapUnavailable:
                return "Forbidden"
            case .unauthorized:
                return "Unauthorized"
            default:
                return "Bad Request"
            }
        }
    }

    struct StoredSettings: Codable {
        struct Passkey: Codable {
            var username: String
            var credentialID: String
            var name: String
            var publicKeyX963: String
            var signCount: UInt32
            var addedAt: Date

            enum CodingKeys: String, CodingKey {
                case username
                case credentialID
                case name
                case publicKeyX963
                case signCount
                case addedAt
            }

            init(username: String, credentialID: String, name: String, publicKeyX963: String, signCount: UInt32, addedAt: Date) {
                self.username = username
                self.credentialID = credentialID
                self.name = name
                self.publicKeyX963 = publicKeyX963
                self.signCount = signCount
                self.addedAt = addedAt
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
                credentialID = try container.decode(String.self, forKey: .credentialID)
                name = try container.decode(String.self, forKey: .name)
                publicKeyX963 = try container.decode(String.self, forKey: .publicKeyX963)
                signCount = try container.decode(UInt32.self, forKey: .signCount)
                addedAt = try container.decode(Date.self, forKey: .addedAt)
            }
        }

        struct Admin: Codable {
            var username: String
            var passwordSalt: String?
            var passwordHash: String?
            var passwordIterations: Int?
            var passwordAlgorithm: String?
            var mustChangePassword: Bool
            var passwordSetupToken: String?
            var createdAt: Date
        }

        var username: String
        var publicBaseURL: String?
        var sessionDurationHours: Int
        var passwordConfigured: Bool
        var passwordSalt: String?
        var passwordHash: String?
        var passwordIterations: Int?
        var passwordAlgorithm: String?
        var admins: [Admin]
        var passkeys: [Passkey]

        enum CodingKeys: String, CodingKey {
            case username
            case publicBaseURL
            case sessionDurationHours
            case passwordConfigured
            case passwordSalt
            case passwordHash
            case passwordIterations
            case passwordAlgorithm
            case admins
            case passkeys
        }

        static let empty = StoredSettings(
            username: "admin",
            publicBaseURL: nil,
            sessionDurationHours: 12,
            passwordConfigured: false,
            passwordSalt: nil,
            passwordHash: nil,
            passwordIterations: nil,
            passwordAlgorithm: nil,
            admins: [],
            passkeys: []
        )

        init(
            username: String,
            publicBaseURL: String?,
            sessionDurationHours: Int,
            passwordConfigured: Bool,
            passwordSalt: String?,
            passwordHash: String?,
            passwordIterations: Int?,
            passwordAlgorithm: String?,
            admins: [Admin],
            passkeys: [Passkey]
        ) {
            self.username = username
            self.publicBaseURL = publicBaseURL
            self.sessionDurationHours = sessionDurationHours
            self.passwordConfigured = passwordConfigured
            self.passwordSalt = passwordSalt
            self.passwordHash = passwordHash
            self.passwordIterations = passwordIterations
            self.passwordAlgorithm = passwordAlgorithm
            self.admins = admins
            self.passkeys = passkeys
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedUsername = try container.decodeIfPresent(String.self, forKey: .username) ?? "admin"
            let decodedPasskeys = (try container.decodeIfPresent([Passkey].self, forKey: .passkeys) ?? []).map { passkey in
                var passkey = passkey
                if passkey.username.isEmpty {
                    passkey.username = decodedUsername
                }
                return passkey
            }
            username = decodedUsername
            publicBaseURL = try container.decodeIfPresent(String.self, forKey: .publicBaseURL)
            sessionDurationHours = try container.decodeIfPresent(Int.self, forKey: .sessionDurationHours) ?? 12
            passwordConfigured = try container.decodeIfPresent(Bool.self, forKey: .passwordConfigured) ?? false
            passwordSalt = try container.decodeIfPresent(String.self, forKey: .passwordSalt)
            passwordHash = try container.decodeIfPresent(String.self, forKey: .passwordHash)
            passwordIterations = try container.decodeIfPresent(Int.self, forKey: .passwordIterations)
            passwordAlgorithm = try container.decodeIfPresent(String.self, forKey: .passwordAlgorithm)
            admins = try container.decodeIfPresent([Admin].self, forKey: .admins) ?? []
            passkeys = decodedPasskeys
        }
    }

    private struct PasswordRecord: Codable {
        var salt: String
        var hash: String
        var iterations: Int
        var algorithm: PasswordAlgorithm
    }

    private struct Session {
        var id: String
        var username: String
        var expiresAt: Date
    }

    struct AuditEntry: Codable {
        var id: String
        var occurredAt: Date
        var username: String?
        var action: String
        var detail: String?
        var remoteAddress: String?
        var userAgent: String?
    }

    private enum ChallengeKind {
        case register(sessionID: String, username: String)
        case authenticate
    }

    private struct PendingChallenge {
        var id: String
        var bytes: Data
        var createdAt: Date
        var rpID: String
        var origin: String
        var kind: ChallengeKind
    }

    private let queue = DispatchQueue(label: "ShipHook.WebDashboardSecurity")
    private let settingsURL: URL
    private let auditLogURL: URL
    private let sessionCookieName = "shiphook_session"
    private let defaultsKey = "ShipHook.WebDashboardSecuritySettings"
    private var settings: StoredSettings
    private var didBootstrapThisLaunch = false
    private var sessions: [String: Session] = [:]
    private var challenges: [String: PendingChallenge] = [:]
    private var failuresByKey: [String: [Date]] = [:]
    private var pendingCookieHeader: String?
    private var auditEntries: [AuditEntry] = []

    init() {
        let baseURL = ConfigStore().appSupportDirectory
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        settingsURL = baseURL.appendingPathComponent("web-dashboard-security.json")
        auditLogURL = baseURL.appendingPathComponent("web-dashboard-audit-log.json")
        settings = (try? Self.loadSettings(from: settingsURL))
            ?? Self.loadSettingsFromDefaults(defaultsKey: defaultsKey)
            ?? .empty
        auditEntries = (try? Self.loadAuditEntries(from: auditLogURL)) ?? []
        migrateLegacySettingsLocked()
        didBootstrapThisLaunch = settings.passwordConfigured || !settings.admins.isEmpty || !settings.passkeys.isEmpty
    }

    var requiresBootstrap: Bool {
        queue.sync {
            !(didBootstrapThisLaunch || settings.passwordConfigured || !settings.admins.isEmpty || !settings.passkeys.isEmpty)
        }
    }

    var hasRegisteredPasskeys: Bool {
        queue.sync { !settings.passkeys.isEmpty }
    }

    func recentAuditEntries(limit: Int = 80) -> [AuditEntry] {
        queue.sync {
            Array(auditEntries.prefix(max(0, limit)))
        }
    }

    func recordAuditEvent(action: String, detail: String? = nil, request: HttpRequest, username: String? = nil) {
        queue.sync {
            appendAuditEntryLocked(
                username: username,
                action: action,
                detail: detail,
                request: request
            )
        }
    }

    func securityState(request: HttpRequest) throws -> WebDashboardSecurityStateResponse {
        guard isAuthorized(request: request) else {
            throw SecurityError.unauthorized
        }
        return queue.sync {
            let currentUsername = currentUsernameUnlocked(request: request) ?? ""
            let admins = settings.admins
                .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
                .map { admin in
                    WebDashboardSecurityStateResponse.Admin(
                        username: admin.username,
                        mustChangePassword: admin.mustChangePassword,
                        createdAt: admin.createdAt,
                        isCurrentUser: admin.username.caseInsensitiveCompare(currentUsername) == .orderedSame
                    )
                }
            let passkeys = settings.passkeys
                .sorted {
                    if $0.username.caseInsensitiveCompare($1.username) == .orderedSame {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
                }
                .map { passkey in
                    WebDashboardSecurityStateResponse.Passkey(
                        username: passkey.username,
                        name: passkey.name,
                        addedAt: passkey.addedAt
                    )
                }
            let audit = Array(auditEntries.prefix(120)).map { entry in
                WebDashboardSecurityStateResponse.AuditEntry(
                    id: entry.id,
                    occurredAt: entry.occurredAt,
                    username: entry.username,
                    action: entry.action,
                    detail: entry.detail,
                    remoteAddress: entry.remoteAddress
                )
            }
            return WebDashboardSecurityStateResponse(
                ok: true,
                currentUsername: currentUsername,
                admins: admins,
                passkeys: passkeys,
                auditEntries: audit
            )
        }
    }

    func isBootstrapRequestAllowed(request: HttpRequest) -> Bool {
        let host = request.headers["host"]?.split(separator: ":").first.map(String.init)?.lowercased()
        let address = request.address?.lowercased() ?? ""
        return (host == "localhost" || host == "127.0.0.1") && (address == "127.0.0.1" || address == "::1" || address == "localhost")
    }

    func isAuthorized(request: HttpRequest) -> Bool {
        queue.sync {
            pruneExpiredSessionsLocked()
            guard let sessionID = sessionID(from: request),
                  let session = sessions[sessionID],
                  session.expiresAt > Date() else {
                return false
            }
            sessions[sessionID]?.expiresAt = Date().addingTimeInterval(TimeInterval(max(1, settings.sessionDurationHours)) * 3600)
            return true
        }
    }

    func pendingCookieHeader(for request: HttpRequest) -> String? {
        queue.sync {
            defer { pendingCookieHeader = nil }
            return pendingCookieHeader
        }
    }

    func logout(request: HttpRequest) {
        queue.sync {
            let username = currentUsernameUnlocked(request: request)
            if let sessionID = sessionID(from: request) {
                sessions.removeValue(forKey: sessionID)
            }
            pendingCookieHeader = cookieHeader(value: "", expiresAt: Date(timeIntervalSince1970: 0), secure: isSecureRequest(request))
            appendAuditEntryLocked(username: username, action: "auth.logout", detail: nil, request: request)
        }
    }

    func completeBootstrap(using payload: WebDashboardAuthSetupRequest, request: HttpRequest) throws -> WebDashboardAuthMessageResponse {
        guard isBootstrapRequestAllowed(request: request) else {
            throw SecurityError.bootstrapUnavailable
        }

        let username = payload.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = payload.password
        guard !username.isEmpty else {
            throw SecurityError.invalidInput("Username is required.")
        }
        guard password.count >= 14 else {
            throw SecurityError.weakPassword
        }

        return try queue.sync {
            settings.username = username
            settings.publicBaseURL = normalizedBaseURL(payload.publicBaseURL)
            settings.sessionDurationHours = max(1, payload.sessionDurationHours ?? 12)
            try storePasswordLocked(password, for: username, mustChangePassword: false, passwordSetupToken: nil)
            settings.passwordConfigured = true
            try persistSettingsLocked()
            didBootstrapThisLaunch = true
            let sessionID = createSessionLocked(username: username, secure: isSecureRequest(request))
            _ = sessionID
            appendAuditEntryLocked(username: username, action: "bootstrap.completed", detail: "Initial administrator created.", request: request)
            return WebDashboardAuthMessageResponse(
                ok: true,
                message: "Administrator account created.",
                passkeysAvailable: !settings.passkeys.isEmpty
            )
        }
    }

    func login(using payload: WebDashboardPasswordLoginRequest, request: HttpRequest) throws -> WebDashboardAuthMessageResponse {
        let username = payload.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(username.lowercased())|\(request.address ?? "")"
        return try queue.sync {
            guard !isRateLimitedLocked(for: key) else {
                appendAuditEntryLocked(username: username.isEmpty ? nil : username, action: "auth.login.rate_limited", detail: nil, request: request)
                throw SecurityError.rateLimited
            }
            guard let admin = adminLocked(username: username),
                  let record = try? loadPasswordRecordLocked(for: username),
                  verifyPassword(payload.password, record: record) else {
                registerFailureLocked(for: key)
                appendAuditEntryLocked(username: username.isEmpty ? nil : username, action: "auth.login.failed", detail: nil, request: request)
                throw SecurityError.invalidCredential
            }
            failuresByKey.removeValue(forKey: key)
            _ = createSessionLocked(username: username, secure: isSecureRequest(request))
            appendAuditEntryLocked(username: username, action: "auth.login.password", detail: nil, request: request)
            return WebDashboardAuthMessageResponse(
                ok: true,
                message: "Signed in.",
                passkeysAvailable: !settings.passkeys.isEmpty,
                requiresPasswordChange: admin.mustChangePassword
            )
        }
    }

    func changePassword(using payload: WebDashboardPasswordChangeRequest, request: HttpRequest) throws {
        guard isAuthorized(request: request) else {
            throw SecurityError.unauthorized
        }
        guard payload.newPassword.count >= 14 else {
            throw SecurityError.weakPassword
        }
        try queue.sync {
            guard let username = currentUsernameUnlocked(request: request),
                  let record = try? loadPasswordRecordLocked(for: username),
                  verifyPassword(payload.currentPassword, record: record) else {
                throw SecurityError.invalidCredential
            }
            try storePasswordLocked(payload.newPassword, for: username, mustChangePassword: false, passwordSetupToken: nil)
            settings.passwordConfigured = true
            try persistSettingsLocked()
            appendAuditEntryLocked(username: username, action: "auth.password.changed", detail: nil, request: request)
        }
    }

    func acceptInvite(using payload: WebDashboardInviteAcceptanceRequest, request: HttpRequest) throws -> WebDashboardAuthMessageResponse {
        let token = payload.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw SecurityError.invalidCredential
        }
        guard payload.newPassword.count >= 14 else {
            throw SecurityError.weakPassword
        }
        return try queue.sync {
            guard let admin = settings.admins.first(where: { $0.passwordSetupToken == token }) else {
                throw SecurityError.invalidCredential
            }
            try storePasswordLocked(payload.newPassword, for: admin.username, mustChangePassword: false, passwordSetupToken: nil)
            settings.passwordConfigured = true
            try persistSettingsLocked()
            _ = createSessionLocked(username: admin.username, secure: isSecureRequest(request))
            appendAuditEntryLocked(username: admin.username, action: "auth.invite.accepted", detail: "Password set from invite/reset link.", request: request)
            return WebDashboardAuthMessageResponse(ok: true, message: "Password set. Signed in.", passkeysAvailable: !settings.passkeys.isEmpty)
        }
    }

    func inviteAdmin(username rawUsername: String, request: HttpRequest) throws -> WebDashboardAdminLinkResponse {
        guard isAuthorized(request: request) else {
            throw SecurityError.unauthorized
        }
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            throw SecurityError.invalidInput("Username is required.")
        }
        return try queue.sync {
            guard adminLocked(username: username) == nil else {
                throw SecurityError.invalidInput("That username already exists.")
            }
            let setupToken = randomData(length: 24).base64URLEncodedString()
            try storePasswordLocked("", for: username, mustChangePassword: true, passwordSetupToken: setupToken, generatePasswordHash: false)
            try persistSettingsLocked()
            appendAuditEntryLocked(username: currentUsernameUnlocked(request: request), action: "admin.invited", detail: "@\(username)", request: request)
            return WebDashboardAdminLinkResponse(
                ok: true,
                username: username,
                loginURL: inviteURLLocked(for: setupToken, request: request),
                message: "Administrator invite created."
            )
        }
    }

    func createPasswordResetLink(for rawUsername: String, request: HttpRequest) throws -> WebDashboardAdminLinkResponse {
        guard isAuthorized(request: request) else {
            throw SecurityError.unauthorized
        }
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return try queue.sync {
            guard adminLocked(username: username) != nil else {
                throw SecurityError.invalidInput("That administrator does not exist.")
            }
            let setupToken = randomData(length: 24).base64URLEncodedString()
            try storePasswordSetupTokenLocked(setupToken, for: username, mustChangePassword: true)
            sessions = sessions.filter { $0.value.username.caseInsensitiveCompare(username) != .orderedSame }
            try persistSettingsLocked()
            appendAuditEntryLocked(username: currentUsernameUnlocked(request: request), action: "admin.password_reset_link.created", detail: "@\(username)", request: request)
            return WebDashboardAdminLinkResponse(
                ok: true,
                username: username,
                loginURL: inviteURLLocked(for: setupToken, request: request),
                message: "Password reset link created."
            )
        }
    }

    func deleteAdmin(username rawUsername: String, request: HttpRequest) throws {
        guard isAuthorized(request: request) else {
            throw SecurityError.unauthorized
        }
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        try queue.sync {
            guard let currentUsername = currentUsernameUnlocked(request: request) else {
                throw SecurityError.unauthorized
            }
            guard currentUsername.caseInsensitiveCompare(username) != .orderedSame else {
                throw SecurityError.invalidInput("You cannot delete the currently signed-in administrator.")
            }
            guard settings.admins.contains(where: { $0.username.caseInsensitiveCompare(username) == .orderedSame }) else {
                throw SecurityError.invalidInput("That administrator does not exist.")
            }
            guard settings.admins.count > 1 else {
                throw SecurityError.invalidInput("ShipHook must keep at least one administrator.")
            }
            settings.admins.removeAll { $0.username.caseInsensitiveCompare(username) == .orderedSame }
            settings.passkeys.removeAll { $0.username.caseInsensitiveCompare(username) == .orderedSame }
            sessions = sessions.filter { $0.value.username.caseInsensitiveCompare(username) != .orderedSame }
            try persistSettingsLocked()
            appendAuditEntryLocked(username: currentUsername, action: "admin.deleted", detail: "@\(username)", request: request)
        }
    }

    func beginPasskeyRegistration(request: HttpRequest) throws -> WebDashboardPasskeyRegistrationOptionsResponse {
        guard isAuthorized(request: request) else {
            throw SecurityError.unauthorized
        }
        let rp = try relyingParty(for: request)
        return try queue.sync {
            guard let sessionID = sessionID(from: request),
                  let username = currentUsernameUnlocked(request: request),
                  let admin = adminLocked(username: username) else {
                throw SecurityError.unauthorized
            }
            let challenge = randomData(length: 32)
            let challengeID = UUID().uuidString.lowercased()
            challenges[challengeID] = PendingChallenge(
                id: challengeID,
                bytes: challenge,
                createdAt: Date(),
                rpID: rp.id,
                origin: rp.origin,
                kind: .register(sessionID: sessionID, username: username)
            )
            return WebDashboardPasskeyRegistrationOptionsResponse(
                ok: true,
                challengeID: challengeID,
                challenge: challenge.base64URLEncodedString(),
                rpID: rp.id,
                rpName: "ShipHook",
                userID: Data(admin.username.utf8).base64URLEncodedString(),
                userName: admin.username,
                userDisplayName: admin.username,
                excludeCredentialIDs: settings.passkeys.filter { $0.username.caseInsensitiveCompare(username) == .orderedSame }.map(\.credentialID),
                timeoutMilliseconds: 60_000
            )
        }
    }

    func finishPasskeyRegistration(using payload: WebDashboardFinishPasskeyRegistrationRequest, request: HttpRequest) throws -> WebDashboardAuthMessageResponse {
        guard isAuthorized(request: request) else {
            throw SecurityError.unauthorized
        }
        return try queue.sync {
            guard let challenge = challenges.removeValue(forKey: payload.challengeID) else {
                throw SecurityError.invalidCredential
            }
            guard case let .register(expectedSessionID, username) = challenge.kind,
                  expectedSessionID == sessionID(from: request) else {
                throw SecurityError.invalidCredential
            }

            let clientData = try decodeClientData(from: payload.clientDataJSON, expectedType: "webauthn.create", challenge: challenge)
            _ = clientData
            let attestation = try Data(base64URLString: payload.attestationObject)
            let registration = try parseRegistration(attestationObject: attestation, expectedRPID: challenge.rpID)
            settings.passkeys.removeAll { $0.credentialID == registration.credentialID.base64URLEncodedString() }
            settings.passkeys.append(
                StoredSettings.Passkey(
                    username: username,
                    credentialID: registration.credentialID.base64URLEncodedString(),
                    name: (payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? payload.name! : "Passkey"),
                    publicKeyX963: registration.publicKeyX963.base64URLEncodedString(),
                    signCount: registration.signCount,
                    addedAt: Date()
                )
            )
            try persistSettingsLocked()
            appendAuditEntryLocked(username: username, action: "auth.passkey.added", detail: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines), request: request)
            return WebDashboardAuthMessageResponse(ok: true, message: "Passkey added.", passkeysAvailable: true)
        }
    }

    func beginPasskeyAuthentication(request: HttpRequest) throws -> WebDashboardPasskeyAuthenticationOptionsResponse {
        let rp = try relyingParty(for: request)
        return try queue.sync {
            guard !settings.passkeys.isEmpty else {
                throw SecurityError.passkeysUnavailable("No passkeys are registered yet.")
            }
            let challengeBytes = randomData(length: 32)
            let challengeID = UUID().uuidString.lowercased()
            challenges[challengeID] = PendingChallenge(
                id: challengeID,
                bytes: challengeBytes,
                createdAt: Date(),
                rpID: rp.id,
                origin: rp.origin,
                kind: .authenticate
            )
            return WebDashboardPasskeyAuthenticationOptionsResponse(
                ok: true,
                challengeID: challengeID,
                challenge: challengeBytes.base64URLEncodedString(),
                rpID: rp.id,
                credentialIDs: settings.passkeys.map(\.credentialID),
                timeoutMilliseconds: 60_000
            )
        }
    }

    func finishPasskeyAuthentication(using payload: WebDashboardFinishPasskeyAuthenticationRequest, request: HttpRequest) throws -> WebDashboardAuthMessageResponse {
        try queue.sync {
            guard let challenge = challenges.removeValue(forKey: payload.challengeID) else {
                throw SecurityError.invalidCredential
            }
            _ = try decodeClientData(from: payload.clientDataJSON, expectedType: "webauthn.get", challenge: challenge)
            guard let index = settings.passkeys.firstIndex(where: { $0.credentialID == payload.credentialID }) else {
                throw SecurityError.invalidCredential
            }
            let authenticatorData = try Data(base64URLString: payload.authenticatorData)
            let signature = try Data(base64URLString: payload.signature)
            try verifyAssertion(
                authenticatorData: authenticatorData,
                clientDataJSONBase64URL: payload.clientDataJSON,
                signatureDER: signature,
                expectedRPID: challenge.rpID,
                passkey: settings.passkeys[index]
            )
            let signCount = readAssertionSignCount(authenticatorData)
            if signCount > settings.passkeys[index].signCount {
                settings.passkeys[index].signCount = signCount
                try persistSettingsLocked()
            }
            _ = createSessionLocked(username: settings.passkeys[index].username, secure: isSecureRequest(request))
            appendAuditEntryLocked(username: settings.passkeys[index].username, action: "auth.login.passkey", detail: settings.passkeys[index].name, request: request)
            return WebDashboardAuthMessageResponse(ok: true, message: "Signed in with passkey.", passkeysAvailable: true)
        }
    }

    func setupPageHTML() -> String {
        pageHTML(
            title: "ShipHook Setup",
            body: """
            <div class="card auth-card">
              \(mastheadHTML())
              <div class="auth-copy">
                <div class="auth-eyebrow">Initial Setup</div>
                <h1>Create admin access</h1>
                <p class="auth-lead">Set up the first administrator from localhost. After this, every dashboard request requires authentication.</p>
              </div>
              <section class="auth-section auth-section-accent">
                <form id="setup-form" method="post" action="/api/auth/setup">
                  <label>Username<input name="username" value="admin" autocomplete="username"></label>
                  <label>Password<input type="password" name="password" autocomplete="new-password"></label>
                  <label>Public Base URL<input name="publicBaseURL" placeholder="https://shiphook.example.com"></label>
                  <label>Session Duration (Hours)<input name="sessionDurationHours" type="number" min="1" max="168" value="12"></label>
                  <button type="submit">Create Administrator</button>
                </form>
              </section>
              <p class="note auth-footnote">Passwords are stored as salted hashes. Passkeys can be added afterwards from Account &amp; Security.</p>
              <div id="status" class="status"></div>
            </div>
            <script>
              document.getElementById('setup-form').addEventListener('submit', async event => {
                event.preventDefault();
                const form = new FormData(event.currentTarget);
                const requestPayload = Object.fromEntries(form.entries());
                requestPayload.sessionDurationHours = Number(requestPayload.sessionDurationHours || 12);
                const response = await fetch('/api/auth/setup', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify(requestPayload)
                });
                const responsePayload = await response.json();
                if (!response.ok || responsePayload.ok === false) {
                  document.getElementById('status').textContent = responsePayload.error || 'Setup failed.';
                  return;
                }
                window.location.href = '/';
              });
            </script>
            """
        )
    }

    func bootstrapLockedPageHTML() -> String {
        pageHTML(
            title: "ShipHook Setup Locked",
            body: """
            <div class="card auth-card">
              \(mastheadHTML())
              <div class="auth-copy">
                <div class="auth-eyebrow">Local Access Required</div>
                <h1>Finish setup on this Mac</h1>
                <p class="auth-lead">Authentication has not been configured yet. Open the dashboard from <code>http://localhost</code> on this machine to complete the initial setup.</p>
              </div>
            </div>
            """
        )
    }

    func inviteAcceptancePageHTML(username: String, token: String) -> String {
        pageHTML(
            title: "ShipHook Invite",
            body: """
            <div class="card auth-card">
              \(mastheadHTML())
              <div class="auth-copy">
                <div class="auth-eyebrow">Administrator Invite</div>
                <h1>Set your password</h1>
                <p class="auth-lead">Finish account setup for @\(escapeHTML(username)) and continue straight to the dashboard.</p>
              </div>
              <section class="auth-section auth-section-accent">
                <form id="invite-accept-form" method="post" action="/api/auth/invite/accept">
                  <input type="hidden" name="token" value="\(escapeHTML(token))">
                  <label>Username<input value="\(escapeHTML(username))" disabled></label>
                  <label>New Password<input type="password" name="newPassword" autocomplete="new-password"></label>
                  <button type="submit">Set Password</button>
                </form>
              </section>
              <div id="status" class="status"></div>
            </div>
            <script>
              const statusNode = document.getElementById('status');
              document.getElementById('invite-accept-form').addEventListener('submit', async event => {
                event.preventDefault();
                const payload = Object.fromEntries(new FormData(event.currentTarget).entries());
                const response = await fetch('/api/auth/invite/accept', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify(payload)
                });
                const result = await response.json();
                if (!response.ok || result.ok === false) {
                  statusNode.textContent = result.error || 'Could not complete setup.';
                  return;
                }
                window.location.href = '/';
              });
            </script>
            """
        )
    }

    func loginPageHTML(passkeysAvailable: Bool) -> String {
        let passkeyButton = passkeysAvailable ? "<button type=\"button\" id=\"passkey-button\" class=\"secondary\">Sign In With Passkey</button>" : ""
        return pageHTML(
            title: "ShipHook Login",
            body: """
            <div class="card auth-card">
              \(mastheadHTML())
              <div class="auth-copy">
                <div class="auth-eyebrow">Authentication</div>
                <h1>Login</h1>
                <p class="auth-lead">Sign in to manage repositories, releases, and build automation.</p>
              </div>
              <section class="auth-section auth-section-accent">
                <form id="login-form" method="post" action="/api/auth/login">
                  <label>Username<input name="username" value="" autocomplete="username"></label>
                  <label>Password<input type="password" name="password" autocomplete="current-password"></label>
                  <div class="auth-actions">
                    <button type="submit">Sign In</button>
                    \(passkeyButton)
                  </div>
                </form>
              </section>
              <div id="status" class="status"></div>
            </div>
            <script>
              const statusNode = document.getElementById('status');
              document.getElementById('login-form').addEventListener('submit', async event => {
                event.preventDefault();
                const form = new FormData(event.currentTarget);
                const response = await fetch('/api/auth/login', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify(Object.fromEntries(form.entries()))
                });
                const payload = await response.json();
                if (!response.ok || payload.ok === false) {
                  statusNode.textContent = payload.error || 'Login failed.';
                  return;
                }
                window.location.href = payload.requiresPasswordChange ? '/security?force-password=1' : '/';
              });
              const passkeyButton = document.getElementById('passkey-button');
              if (passkeyButton) {
                passkeyButton.addEventListener('click', async () => {
                  statusNode.textContent = '';
                  const beginResponse = await fetch('/api/auth/passkeys/authenticate/begin', { method: 'POST' });
                  const beginPayload = await beginResponse.json();
                  if (!beginResponse.ok || beginPayload.ok === false) {
                    statusNode.textContent = beginPayload.error || 'Passkey login failed.';
                    return;
                  }
                  const assertion = await navigator.credentials.get({
                    publicKey: {
                      challenge: base64URLToBuffer(beginPayload.challenge),
                      rpId: beginPayload.rpID,
                      allowCredentials: beginPayload.credentialIDs.map(id => ({ id: base64URLToBuffer(id), type: 'public-key' })),
                      timeout: beginPayload.timeoutMilliseconds,
                      userVerification: 'required'
                    }
                  });
                  const finishResponse = await fetch('/api/auth/passkeys/authenticate/finish', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                      challengeID: beginPayload.challengeID,
                      credentialID: bufferToBase64URL(assertion.rawId),
                      clientDataJSON: bufferToBase64URL(assertion.response.clientDataJSON),
                      authenticatorData: bufferToBase64URL(assertion.response.authenticatorData),
                      signature: bufferToBase64URL(assertion.response.signature),
                      userHandle: assertion.response.userHandle ? bufferToBase64URL(assertion.response.userHandle) : null
                    })
                  });
                  const finishPayload = await finishResponse.json();
                  if (!finishResponse.ok || finishPayload.ok === false) {
                    statusNode.textContent = finishPayload.error || 'Passkey login failed.';
                    return;
                  }
                  window.location.href = '/';
                });
              }
              function base64URLToBuffer(value) {
                const base64 = value.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((value.length + 3) % 4);
                const binary = atob(base64);
                return Uint8Array.from(binary, char => char.charCodeAt(0));
              }
              function bufferToBase64URL(buffer) {
                const bytes = new Uint8Array(buffer);
                let binary = '';
                bytes.forEach(byte => binary += String.fromCharCode(byte));
                return btoa(binary).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/g, '');
              }
            </script>
            """
        )
    }

    private func auditLogHTML() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let entries = recentAuditEntries()
        guard !entries.isEmpty else {
            return "<p class=\"note\">No audit entries recorded yet.</p>"
        }

        let items = entries.map { entry in
            let timestamp = formatter.string(from: entry.occurredAt)
            let username = entry.username.map { "@\(escapeHTML($0))" } ?? "Unknown user"
            let detail = entry.detail.map { "<div class=\"tiny\">\(escapeHTML($0))</div>" } ?? ""
            let remote = entry.remoteAddress.map { "<div class=\"tiny\">IP \(escapeHTML($0))</div>" } ?? ""
            return """
            <div class="audit-entry">
              <div class="audit-entry-main">
                <strong>\(escapeHTML(entry.action))</strong>
                <span class="note">\(username)</span>
              </div>
              <div class="tiny">\(escapeHTML(timestamp))</div>
              \(detail)
              \(remote)
            </div>
            """
        }.joined()

        return "<div class=\"audit-list\">\(items)</div>"
    }

    func securityPageHTML(forcePassword: Bool, currentUsername: String) -> String {
        let passkeyList = settings.passkeys.isEmpty
            ? "<p class=\"note\">No passkeys registered yet.</p>"
            : "<ul>" + settings.passkeys
                .sorted {
                    if $0.username.caseInsensitiveCompare($1.username) == .orderedSame {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
                }
                .map { "<li>@\(escapeHTML($0.username)) <span class=\"note\">· \(escapeHTML($0.name))</span></li>" }
                .joined() + "</ul>"
        let adminList = settings.admins
            .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            .map { admin in
                let resetButton = "<button type=\"button\" class=\"secondary\" data-admin-reset=\"\(escapeHTML(admin.username))\">Reset Password</button>"
                let deleteButton = currentUsername.caseInsensitiveCompare(admin.username) == .orderedSame
                    ? ""
                    : "<button type=\"button\" class=\"secondary warn\" data-admin-delete=\"\(escapeHTML(admin.username))\">Delete</button>"
                return """
                <li class="admin-row">
                  <div class="admin-row-copy">
                    <strong>@\(escapeHTML(admin.username))</strong>
                    \(admin.mustChangePassword ? "<span class=\"note\">needs password setup</span>" : "")
                  </div>
                  <div class="admin-row-actions">\(resetButton)\(deleteButton)</div>
                </li>
                """
            }
            .joined()
        let forceNote = forcePassword ? "<p class=\"note strong\">This account must set a new password before returning to the dashboard.</p>" : ""
        return pageHTML(
            title: "ShipHook Security",
            body: """
            <div class="card auth-card">
              \(mastheadHTML())
              <div class="toolbar"><a href=\"/\">Dashboard</a><button type=\"button\" id=\"logout\" class=\"secondary\">Sign Out</button></div>
              <div class="auth-copy">
                <div class="auth-eyebrow">Account</div>
                <h1>Security</h1>
                <p class="auth-lead">Signed in as @\(escapeHTML(currentUsername)). Manage password access, administrators, and passkeys.</p>
                \(forceNote)
              </div>
              <section class="auth-section">
                <h2>Password</h2>
                <form id="password-form" method="post" action="/api/auth/change-password">
                  <label>Current Password<input type="password" name="currentPassword" autocomplete="current-password"></label>
                  <label>New Password<input type="password" name="newPassword" autocomplete="new-password"></label>
                  <button type="submit">Change Password</button>
                </form>
              </section>
              <section class="auth-section">
                <h2>Passkeys</h2>
                \(passkeyList)
                <button type="button" id="register-passkey">Register Passkey</button>
                <p class="note">Passkeys work with platform authenticators such as iCloud Keychain when the browser and origin support WebAuthn.</p>
              </section>
              <section class="auth-section">
                <h2>Administrators</h2>
                <ul class="admin-list">\(adminList)</ul>
                <form id="invite-admin-form">
                  <label>Username<input name="username" autocomplete="off" placeholder="teammate"></label>
                  <button type="submit">Add Administrator</button>
                </form>
                <div id="invite-output" class="invite-output"></div>
              </section>
              <section class="auth-section">
                <h2>Audit Log</h2>
                \(auditLogHTML())
              </section>
              <div id="status" class="status"></div>
            </div>
            <script>
              const statusNode = document.getElementById('status');
              const inviteOutputNode = document.getElementById('invite-output');
              document.getElementById('logout').addEventListener('click', async () => {
                await fetch('/api/auth/logout', { method: 'POST' });
                window.location.href = '/';
              });
              document.getElementById('password-form').addEventListener('submit', async event => {
                event.preventDefault();
                const payload = Object.fromEntries(new FormData(event.currentTarget).entries());
                const response = await fetch('/api/auth/change-password', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify(payload)
                });
                const result = await response.json();
                statusNode.textContent = result.message || result.error || '';
                if (result.message && \(forcePassword ? "true" : "false")) {
                  window.location.href = '/';
                }
              });
              document.getElementById('invite-admin-form').addEventListener('submit', async event => {
                event.preventDefault();
                const payload = Object.fromEntries(new FormData(event.currentTarget).entries());
                const response = await fetch('/api/auth/admins/invite', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify(payload)
                });
                const result = await response.json();
                if (!response.ok || result.ok === false) {
                  statusNode.textContent = result.error || 'Failed to create administrator.';
                  return;
                }
                inviteOutputNode.innerHTML = `
                  <div class="invite-card">
                    <div><strong>@${escapeHTML(result.username)}</strong></div>
                    <div>Password setup link: <a href="${escapeAttribute(result.loginURL)}">${escapeHTML(result.loginURL)}</a></div>
                  </div>
                `;
                event.currentTarget.reset();
                statusNode.textContent = result.message || '';
              });
              document.querySelectorAll('[data-admin-reset]').forEach(button => {
                button.addEventListener('click', async event => {
                  const username = event.currentTarget.dataset.adminReset;
                  const response = await fetch('/api/auth/admins/reset', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ username })
                  });
                  const result = await response.json();
                  if (!response.ok || result.ok === false) {
                    statusNode.textContent = result.error || 'Failed to create reset link.';
                    return;
                  }
                  inviteOutputNode.innerHTML = `
                    <div class="invite-card">
                      <div><strong>@${escapeHTML(result.username)}</strong></div>
                      <div>Password reset link: <a href="${escapeAttribute(result.loginURL)}">${escapeHTML(result.loginURL)}</a></div>
                    </div>
                  `;
                  statusNode.textContent = result.message || '';
                });
              });
              document.querySelectorAll('[data-admin-delete]').forEach(button => {
                button.addEventListener('click', async event => {
                  const username = event.currentTarget.dataset.adminDelete;
                  if (!window.confirm(`Delete administrator @${username}?`)) {
                    return;
                  }
                  const response = await fetch('/api/auth/admins/delete', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ username })
                  });
                  const result = await response.json();
                  if (!response.ok || result.ok === false) {
                    statusNode.textContent = result.error || 'Failed to delete administrator.';
                    return;
                  }
                  window.location.reload();
                });
              });
              document.getElementById('register-passkey').addEventListener('click', async () => {
                if (!window.PublicKeyCredential || !navigator.credentials?.create) {
                  statusNode.textContent = 'This browser does not support passkey creation.';
                  return;
                }
                try {
                  const beginResponse = await fetch('/api/auth/passkeys/register/begin', { method: 'POST' });
                  const beginPayload = await beginResponse.json();
                  if (!beginResponse.ok || beginPayload.ok === false) {
                    statusNode.textContent = beginPayload.error || 'Passkey setup failed.';
                    return;
                  }
                  const credential = await navigator.credentials.create({
                    publicKey: {
                      challenge: base64URLToBuffer(beginPayload.challenge),
                      rp: { id: beginPayload.rpID, name: beginPayload.rpName },
                      user: {
                        id: base64URLToBuffer(beginPayload.userID),
                        name: beginPayload.userName,
                        displayName: beginPayload.userDisplayName
                      },
                      pubKeyCredParams: [{ type: 'public-key', alg: -7 }],
                      timeout: beginPayload.timeoutMilliseconds,
                      attestation: 'none',
                      authenticatorSelection: {
                        residentKey: 'preferred',
                        userVerification: 'required'
                      },
                      excludeCredentials: beginPayload.excludeCredentialIDs.map(id => ({ id: base64URLToBuffer(id), type: 'public-key' }))
                    }
                  });
                  const finishResponse = await fetch('/api/auth/passkeys/register/finish', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                      challengeID: beginPayload.challengeID,
                      name: '',
                      credentialID: bufferToBase64URL(credential.rawId),
                      clientDataJSON: bufferToBase64URL(credential.response.clientDataJSON),
                      attestationObject: bufferToBase64URL(credential.response.attestationObject)
                    })
                  });
                  const finishPayload = await finishResponse.json();
                  if (!finishResponse.ok || finishPayload.ok === false) {
                    statusNode.textContent = finishPayload.error || 'Passkey setup failed.';
                    return;
                  }
                  window.location.reload();
                } catch (error) {
                  statusNode.textContent = error?.message || 'Passkey setup failed.';
                }
              });
              function base64URLToBuffer(value) {
                const base64 = value.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((value.length + 3) % 4);
                const binary = atob(base64);
                return Uint8Array.from(binary, char => char.charCodeAt(0));
              }
              function bufferToBase64URL(buffer) {
                const bytes = new Uint8Array(buffer);
                let binary = '';
                bytes.forEach(byte => binary += String.fromCharCode(byte));
                return btoa(binary).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/g, '');
              }
              function escapeHTML(value) {
                return String(value ?? '')
                  .replace(/&/g, '&amp;')
                  .replace(/</g, '&lt;')
                  .replace(/>/g, '&gt;')
                  .replace(/"/g, '&quot;');
              }
              function escapeAttribute(value) {
                return escapeHTML(value);
              }
            </script>
            """
        )
    }

    private func authPageVersionLabel() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines), buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty && short != build:
            return "v\(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return "v\(short)"
        case let (_, build?) where !build.isEmpty:
            return "v\(build)"
        default:
            return ""
        }
    }

    private func mastheadHTML() -> String {
        let versionLabel = authPageVersionLabel()
        let versionHTML = versionLabel.isEmpty ? "" : "<div class=\"auth-masthead-version\">\(escapeHTML(versionLabel))</div>"
        return """
        <div class="auth-masthead">
          <div class="auth-masthead-brand">
            <picture>
              <source media="(prefers-color-scheme: dark)" srcset="/assets/glyph-dark.png">
              <img class="auth-glyph" src="/assets/glyph-light.png" alt="">
            </picture>
            <h1 class="auth-wordmark">ShipHook</h1>
          </div>
          \(versionHTML)
        </div>
        """
    }

    private func pageHTML(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="robots" content="noindex,nofollow,noarchive">
          <title>\(title)</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: radial-gradient(circle at top left, rgba(255,135,91,0.12), transparent 28%), radial-gradient(circle at 88% 10%, rgba(77,184,255,0.10), transparent 24%), linear-gradient(180deg, #0f131b, #151c28); color: #f5f7fb; padding: 16px; }
            .card { width: min(680px, calc(100vw - 32px)); padding: 28px; border-radius: 24px; background: rgba(16, 21, 30, 0.94); border: 1px solid rgba(255,255,255,0.08); box-shadow: 0 24px 64px rgba(0,0,0,0.32); }
            .auth-card { overflow: hidden; display: grid; gap: 18px; backdrop-filter: blur(14px); }
            .auth-masthead { position: relative; overflow: hidden; display: flex; align-items: center; justify-content: space-between; gap: 16px; border-radius: 18px; padding: 16px 18px; margin-bottom: 18px; border: 1px solid rgba(255,255,255,0.08); background: linear-gradient(135deg, rgba(255,135,91,0.14), rgba(77,184,255,0.05) 52%, rgba(255,224,130,0.06)), rgba(25, 31, 42, 0.92); }
            .auth-masthead-brand { display: inline-flex; align-items: center; gap: 12px; min-width: 0; }
            .auth-glyph { width: 34px; height: 34px; object-fit: contain; }
            .auth-wordmark { margin: 0; font: 600 32px/0.92 "Iowan Old Style", "Palatino Linotype", serif; letter-spacing: -0.03em; }
            .auth-masthead-version { flex: 0 0 auto; color: rgba(245,247,251,0.48); font: 500 12px/1.2 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; letter-spacing: 0.02em; white-space: nowrap; }
            .auth-copy { display: grid; gap: 10px; margin-bottom: 2px; }
            .auth-eyebrow { color: rgba(245,247,251,0.50); font: 600 11px/1 var(--font-mono, ui-monospace, monospace); letter-spacing: 0.14em; text-transform: uppercase; }
            .auth-copy h1 { margin: 0; font: 600 34px/0.95 "Iowan Old Style", "Palatino Linotype", serif; letter-spacing: -0.03em; }
            .auth-lead { margin: 0; font-size: 15px; color: rgba(245,247,251,0.72); max-width: 46ch; }
            h1, h2 { margin: 0 0 12px; }
            p, li { color: rgba(245,247,251,0.76); line-height: 1.5; }
            form, section { display: grid; gap: 14px; margin-top: 0; }
            label { display: grid; gap: 6px; font-weight: 600; }
            input { border-radius: 12px; border: 1px solid rgba(255,255,255,0.10); background: rgba(255,255,255,0.05); color: inherit; padding: 12px 14px; }
            button, a { display: inline-flex; align-items: center; justify-content: center; border-radius: 12px; border: 1px solid rgba(255,255,255,0.10); background: linear-gradient(135deg, rgba(255,135,91,0.28), rgba(255,135,91,0.12)); color: inherit; padding: 11px 14px; text-decoration: none; cursor: pointer; }
            button.secondary, a.secondary { background: rgba(255,255,255,0.05); }
            button.warn, a.warn { border-color: rgba(255,109,122,0.24); background: linear-gradient(135deg, rgba(255,109,122,0.20), rgba(255,109,122,0.08)); }
            .toolbar { display: flex; gap: 10px; margin: -2px 0 4px; }
            .auth-section { padding: 18px; border-radius: 18px; border: 1px solid rgba(255,255,255,0.08); background: linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0.02)); }
            .auth-section-accent { background: linear-gradient(180deg, rgba(255,135,91,0.10), rgba(77,184,255,0.04) 68%, rgba(255,255,255,0.02)); }
            .auth-section h2 { margin-bottom: 10px; font: 700 20px/1.05 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; letter-spacing: -0.02em; }
            .auth-actions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 4px; }
            .auth-footnote { margin-top: -4px; }
            .status { min-height: 1.4em; margin-top: 2px; color: #ffbe55; font-weight: 600; }
            .note, code { color: rgba(245,247,251,0.62); }
            .note.strong { color: rgba(245,247,251,0.88); }
            .invite-output { display: grid; gap: 10px; }
            .invite-card { margin-top: 6px; padding: 14px; border-radius: 14px; border: 1px solid rgba(255,255,255,0.08); background: rgba(255,255,255,0.04); display: grid; gap: 6px; word-break: break-word; }
            .admin-list { list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; }
            .admin-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 14px; border-radius: 14px; border: 1px solid rgba(255,255,255,0.06); background: rgba(255,255,255,0.03); }
            .admin-row-copy { display: grid; gap: 4px; min-width: 0; }
            .admin-row-actions { display: flex; flex-wrap: wrap; gap: 8px; }
            .admin-row-actions button { padding: 9px 12px; }
            .audit-list { display: grid; gap: 10px; }
            .audit-entry { padding: 12px 14px; border-radius: 14px; border: 1px solid rgba(255,255,255,0.06); background: rgba(255,255,255,0.03); display: grid; gap: 4px; }
            .audit-entry-main { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
            ul { padding-left: 18px; }
            @media (prefers-color-scheme: light) {
              body { background: linear-gradient(180deg, #edf2f7, #dfe8f3); color: #132033; }
              .card { background: rgba(255,255,255,0.94); border-color: rgba(19,32,51,0.10); }
              .auth-masthead { border-color: rgba(33,49,76,0.10); background: linear-gradient(135deg, rgba(255,135,91,0.14), rgba(77,184,255,0.05) 52%, rgba(255,224,130,0.06)), rgba(252,253,255,0.94); }
              .auth-masthead-version { color: rgba(19,32,51,0.44); }
              .auth-eyebrow { color: rgba(19,32,51,0.46); }
              .auth-lead { color: rgba(19,32,51,0.70); }
              p, li, .note, code { color: rgba(19,32,51,0.70); }
              input { background: rgba(19,32,51,0.04); border-color: rgba(19,32,51,0.12); color: #132033; }
              button.secondary, a.secondary { background: rgba(19,32,51,0.04); }
              button.warn, a.warn { border-color: rgba(209,78,92,0.20); background: linear-gradient(135deg, rgba(209,78,92,0.16), rgba(209,78,92,0.06)); }
              .auth-section { background: linear-gradient(180deg, rgba(19,32,51,0.03), rgba(19,32,51,0.02)); border-color: rgba(19,32,51,0.08); }
              .auth-section-accent { background: linear-gradient(180deg, rgba(216,106,56,0.10), rgba(34,123,189,0.04) 68%, rgba(19,32,51,0.02)); }
              .invite-card { background: rgba(19,32,51,0.04); border-color: rgba(19,32,51,0.08); }
              .admin-row { background: rgba(19,32,51,0.03); border-color: rgba(19,32,51,0.08); }
              .audit-entry { background: rgba(19,32,51,0.03); border-color: rgba(19,32,51,0.08); }
            }
            @media (max-width: 720px) {
              .card { width: min(680px, calc(100vw - 20px)); padding: 18px; border-radius: 20px; }
              .auth-copy h1 { font-size: 29px; }
              .auth-masthead { padding: 14px 15px; }
              .auth-section { padding: 14px; }
              .toolbar, .auth-actions { grid-template-columns: 1fr; }
              .toolbar, .auth-actions { display: grid; }
              .admin-row { align-items: stretch; flex-direction: column; }
              .admin-row-actions { width: 100%; }
            }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private func normalizedBaseURL(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), scheme == "https" || host == "localhost" else {
            return nil
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.string
    }

    private func relyingParty(for request: HttpRequest) throws -> (id: String, origin: String) {
        if let requestOrigin = resolvedRequestOrigin(for: request),
           let requestHost = requestHost(for: request) {
            if requestHost == "localhost" || requestHost == "127.0.0.1" {
                return ("localhost", requestOrigin.replacingOccurrences(of: "127.0.0.1", with: "localhost"))
            }
            if let baseURL = queue.sync(execute: { settings.publicBaseURL }),
               let url = URL(string: baseURL),
               let host = url.host?.lowercased(),
               host == requestHost {
                return (host, baseURL)
            }
            if isSecureRequest(request) {
                return (requestHost, requestOrigin)
            }
        }
        if let baseURL = queue.sync(execute: { settings.publicBaseURL }),
           let url = URL(string: baseURL),
           let host = url.host?.lowercased() {
            return (host, baseURL)
        }
        throw SecurityError.passkeysUnavailable("Passkeys require localhost access or a matching HTTPS public base URL.")
    }

    func usernameForPasswordSetupToken(_ token: String?) -> String? {
        guard let token, !token.isEmpty else { return nil }
        return queue.sync {
            settings.admins.first(where: { $0.passwordSetupToken == token })?.username
        }
    }

    private func requestHost(for request: HttpRequest) -> String? {
        request.headers["host"]?.split(separator: ":").first.map(String.init)?.lowercased()
    }

    private func resolvedRequestOrigin(for request: HttpRequest) -> String? {
        guard let host = request.headers["host"] else {
            return nil
        }
        let scheme = isSecureRequest(request) ? "https" : "http"
        return "\(scheme)://\(host)"
    }

    private func createSessionLocked(username: String, secure: Bool) -> String {
        pruneExpiredSessionsLocked()
        let token = randomData(length: 32).base64URLEncodedString()
        let expiry = Date().addingTimeInterval(TimeInterval(max(1, settings.sessionDurationHours)) * 3600)
        sessions[token] = Session(id: token, username: username, expiresAt: expiry)
        pendingCookieHeader = cookieHeader(value: token, expiresAt: expiry, secure: secure)
        return token
    }

    private func cookieHeader(value: String, expiresAt: Date, secure: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        var attributes = [
            "\(sessionCookieName)=\(value)",
            "Path=/",
            "HttpOnly",
            "SameSite=Strict",
            "Expires=\(formatter.string(from: expiresAt))"
        ]
        if secure {
            attributes.append("Secure")
        }
        return attributes.joined(separator: "; ")
    }

    private func sessionID(from request: HttpRequest) -> String? {
        request.headers["cookie"]?
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(sessionCookieName)=") }
            .map { String($0.dropFirst(sessionCookieName.count + 1)) }
    }

    private func pruneExpiredSessionsLocked() {
        let now = Date()
        sessions = sessions.filter { $0.value.expiresAt > now }
        challenges = challenges.filter { now.timeIntervalSince($0.value.createdAt) < 300 }
    }

    private func isSecureRequest(_ request: HttpRequest) -> Bool {
        if request.headers["x-forwarded-proto"]?.lowercased() == "https" {
            return true
        }
        if request.headers["cf-visitor"]?.contains("\"https\"") == true {
            return true
        }
        if let host = request.headers["host"]?.lowercased(), host.hasPrefix("localhost") {
            return false
        }
        return false
    }

    private func isRateLimitedLocked(for key: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-900)
        let attempts = failuresByKey[key, default: []].filter { $0 > cutoff }
        failuresByKey[key] = attempts
        return attempts.count >= 8
    }

    private func registerFailureLocked(for key: String) {
        failuresByKey[key, default: []].append(Date())
    }

    private func persistSettingsLocked() throws {
        let encoder = JSONEncoder.webDashboard
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func loadSettings(from url: URL) throws -> StoredSettings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.webDashboard.decode(StoredSettings.self, from: data)
    }

    private func persistAuditEntriesLocked() throws {
        let encoder = JSONEncoder.webDashboard
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Array(auditEntries.prefix(500)))
        try data.write(to: auditLogURL, options: .atomic)
    }

    private static func loadAuditEntries(from url: URL) throws -> [AuditEntry] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.webDashboard.decode([AuditEntry].self, from: data)
    }

    private static func loadSettingsFromDefaults(defaultsKey: String) -> StoredSettings? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder.webDashboard.decode(StoredSettings.self, from: data)
    }

    private func appendAuditEntryLocked(username: String?, action: String, detail: String?, request: HttpRequest) {
        let entry = AuditEntry(
            id: UUID().uuidString.lowercased(),
            occurredAt: Date(),
            username: username,
            action: action,
            detail: detail,
            remoteAddress: remoteAddress(for: request),
            userAgent: request.headers["user-agent"]
        )
        auditEntries.insert(entry, at: 0)
        if auditEntries.count > 500 {
            auditEntries.removeLast(auditEntries.count - 500)
        }
        try? persistAuditEntriesLocked()
    }

    private func remoteAddress(for request: HttpRequest) -> String? {
        if let cf = request.headers["cf-connecting-ip"], !cf.isEmpty {
            return cf
        }
        if let forwarded = request.headers["x-forwarded-for"]?
            .split(separator: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !forwarded.isEmpty {
            return forwarded
        }
        return request.address
    }

    private func storePasswordLocked(_ password: String) throws {
        try storePasswordLocked(password, for: settings.username, mustChangePassword: false, passwordSetupToken: nil)
    }

    private func loadPasswordRecordLocked() throws -> PasswordRecord {
        try loadPasswordRecordLocked(for: settings.username)
    }

    private func storePasswordLocked(_ password: String, for username: String, mustChangePassword: Bool, passwordSetupToken: String?, generatePasswordHash: Bool = true) throws {
        let salt = randomData(length: 16)
        let iterations = 310_000
        let saltString = salt.base64URLEncodedString()
        let hashString = generatePasswordHash ? Self.derivePasswordHash(password: password, salt: salt, iterations: iterations, algorithm: .pbkdf2SHA256).base64URLEncodedString() : nil

        if let index = settings.admins.firstIndex(where: { $0.username.caseInsensitiveCompare(username) == .orderedSame }) {
            settings.admins[index].passwordSalt = generatePasswordHash ? saltString : nil
            settings.admins[index].passwordHash = hashString
            settings.admins[index].passwordIterations = generatePasswordHash ? iterations : nil
            settings.admins[index].passwordAlgorithm = generatePasswordHash ? PasswordAlgorithm.pbkdf2SHA256.rawValue : nil
            settings.admins[index].mustChangePassword = mustChangePassword
            settings.admins[index].passwordSetupToken = passwordSetupToken
        } else {
            settings.admins.append(
                StoredSettings.Admin(
                    username: username,
                    passwordSalt: generatePasswordHash ? saltString : nil,
                    passwordHash: hashString,
                    passwordIterations: generatePasswordHash ? iterations : nil,
                    passwordAlgorithm: generatePasswordHash ? PasswordAlgorithm.pbkdf2SHA256.rawValue : nil,
                    mustChangePassword: mustChangePassword,
                    passwordSetupToken: passwordSetupToken,
                    createdAt: Date()
                )
            )
        }

        if settings.username.caseInsensitiveCompare(username) == .orderedSame, generatePasswordHash {
            settings.passwordSalt = saltString
            settings.passwordHash = hashString
            settings.passwordIterations = iterations
            settings.passwordAlgorithm = PasswordAlgorithm.pbkdf2SHA256.rawValue
            settings.passwordConfigured = true
        }
    }

    private func storePasswordSetupTokenLocked(_ token: String, for username: String, mustChangePassword: Bool) throws {
        guard let index = settings.admins.firstIndex(where: { $0.username.caseInsensitiveCompare(username) == .orderedSame }) else {
            throw SecurityError.invalidInput("That administrator does not exist.")
        }
        settings.admins[index].passwordSetupToken = token
        settings.admins[index].mustChangePassword = mustChangePassword
    }

    private func loadPasswordRecordLocked(for username: String) throws -> PasswordRecord {
        guard let admin = adminLocked(username: username),
              let salt = admin.passwordSalt,
              let hash = admin.passwordHash,
              let iterations = admin.passwordIterations else {
            throw SecurityError.invalidCredential
        }
        let algorithm = PasswordAlgorithm(rawValue: admin.passwordAlgorithm ?? settings.passwordAlgorithm ?? "") ?? .legacyIteratedSHA256
        return PasswordRecord(salt: salt, hash: hash, iterations: iterations, algorithm: algorithm)
    }

    private func adminLocked(username: String) -> StoredSettings.Admin? {
        settings.admins.first { $0.username.caseInsensitiveCompare(username) == .orderedSame }
    }

    func currentUsername(request: HttpRequest) -> String? {
        queue.sync {
            guard let sessionID = sessionID(from: request) else { return nil }
            return sessions[sessionID]?.username
        }
    }

    func requiresPasswordChange(request: HttpRequest) -> Bool {
        queue.sync {
            guard let username = currentUsernameUnlocked(request: request),
                  let admin = adminLocked(username: username) else {
                return false
            }
            return admin.mustChangePassword
        }
    }

    private func currentUsernameUnlocked(request: HttpRequest) -> String? {
        guard let sessionID = sessionID(from: request) else { return nil }
        return sessions[sessionID]?.username
    }

    private func migrateLegacySettingsLocked() {
        if settings.admins.isEmpty,
           let salt = settings.passwordSalt,
           let hash = settings.passwordHash,
           let iterations = settings.passwordIterations {
            settings.admins = [
                StoredSettings.Admin(
                    username: settings.username,
                    passwordSalt: salt,
                    passwordHash: hash,
                    passwordIterations: iterations,
                    passwordAlgorithm: settings.passwordAlgorithm ?? PasswordAlgorithm.legacyIteratedSHA256.rawValue,
                    mustChangePassword: false,
                    passwordSetupToken: nil,
                    createdAt: Date()
                )
            ]
            settings.passwordConfigured = true
            try? persistSettingsLocked()
        }
        if settings.passwordAlgorithm == nil, settings.passwordHash != nil {
            settings.passwordAlgorithm = PasswordAlgorithm.legacyIteratedSHA256.rawValue
        }
        for index in settings.admins.indices {
            if settings.admins[index].passwordAlgorithm == nil, settings.admins[index].passwordHash != nil {
                settings.admins[index].passwordAlgorithm = settings.passwordAlgorithm ?? PasswordAlgorithm.legacyIteratedSHA256.rawValue
            }
            if settings.passkeys.isEmpty == false, settings.admins[index].passwordSetupToken == "" {
                settings.admins[index].passwordSetupToken = nil
            }
        }
        for index in settings.passkeys.indices where settings.passkeys[index].username.isEmpty {
            settings.passkeys[index].username = settings.username
        }
    }

    private func inviteURLLocked(for token: String, request: HttpRequest) -> String {
        let origin = resolvedRequestOrigin(for: request) ?? settings.publicBaseURL ?? "http://localhost"
        return "\(origin)/?invite=\(token)"
    }

    private static func derivePasswordHash(password: String, salt: Data, iterations: Int, algorithm: PasswordAlgorithm) -> Data {
        switch algorithm {
        case .legacyIteratedSHA256:
            var input = Data(password.utf8) + salt
            for _ in 0..<iterations {
                input = Data(SHA256.hash(data: input))
            }
            return input
        case .pbkdf2SHA256:
            return pbkdf2SHA256(password: Data(password.utf8), salt: salt, iterations: iterations, keyLength: 32)
        }
    }

    private func verifyPassword(_ password: String, record: PasswordRecord) -> Bool {
        guard let salt = try? Data(base64URLString: record.salt),
              let stored = try? Data(base64URLString: record.hash) else {
            return false
        }
        let candidate = Self.derivePasswordHash(password: password, salt: salt, iterations: record.iterations, algorithm: record.algorithm)
        return constantTimeEquals(candidate, stored)
    }

    private static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        let hmacLength = 32
        let blockCount = Int(ceil(Double(keyLength) / Double(hmacLength)))
        let key = SymmetricKey(data: password)
        var derived = Data()

        for blockIndex in 1...blockCount {
            var saltBlock = salt
            saltBlock.append(UInt8((blockIndex >> 24) & 0xff))
            saltBlock.append(UInt8((blockIndex >> 16) & 0xff))
            saltBlock.append(UInt8((blockIndex >> 8) & 0xff))
            saltBlock.append(UInt8(blockIndex & 0xff))

            var u = Data(HMAC<SHA256>.authenticationCode(for: saltBlock, using: key))
            var t = u

            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for index in t.indices {
                        t[index] ^= u[index]
                    }
                }
            }

            derived.append(t)
        }

        return derived.prefix(keyLength)
    }

    private func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func randomData(length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes)
    }

    private func decodeClientData(from base64URL: String, expectedType: String, challenge: PendingChallenge) throws -> [String: String] {
        let data = try Data(base64URLString: base64URL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String,
              let challengeValue = object["challenge"] as? String,
              let origin = object["origin"] as? String,
              type == expectedType,
              challengeValue == challenge.bytes.base64URLEncodedString(),
              origin == challenge.origin else {
            throw SecurityError.invalidCredential
        }
        return ["challenge": challengeValue, "origin": origin]
    }

    private func parseRegistration(attestationObject: Data, expectedRPID: String) throws -> (credentialID: Data, publicKeyX963: Data, signCount: UInt32) {
        var decoder = WebDashboardCBORDecoder(data: attestationObject)
        let cbor = try decoder.decodeItem()
        guard let map = cbor.mapValue,
              let authData = map[string: "authData"]?.bytesValue else {
            throw SecurityError.invalidCredential
        }
        let parsed = try parseAuthenticatorData(authData, expectedRPID: expectedRPID, requireAttestedCredentialData: true)
        return (parsed.credentialID ?? Data(), parsed.publicKeyX963 ?? Data(), parsed.signCount)
    }

    private func verifyAssertion(
        authenticatorData: Data,
        clientDataJSONBase64URL: String,
        signatureDER: Data,
        expectedRPID: String,
        passkey: StoredSettings.Passkey
    ) throws {
        _ = try parseAuthenticatorData(authenticatorData, expectedRPID: expectedRPID, requireAttestedCredentialData: false)
        let clientDataJSON = try Data(base64URLString: clientDataJSONBase64URL)
        let clientHash = Data(SHA256.hash(data: clientDataJSON))
        var signedData = authenticatorData
        signedData.append(clientHash)
        let publicKey = try P256.Signing.PublicKey(x963Representation: Data(base64URLString: passkey.publicKeyX963))
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureDER)
        guard publicKey.isValidSignature(signature, for: signedData) else {
            throw SecurityError.invalidCredential
        }
    }

    private func readAssertionSignCount(_ authenticatorData: Data) -> UInt32 {
        guard authenticatorData.count >= 37 else { return 0 }
        return authenticatorData.subdata(in: 33..<37).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    private func parseAuthenticatorData(
        _ data: Data,
        expectedRPID: String,
        requireAttestedCredentialData: Bool
    ) throws -> (signCount: UInt32, credentialID: Data?, publicKeyX963: Data?) {
        guard data.count >= 37 else {
            throw SecurityError.invalidCredential
        }
        let rpHash = Data(SHA256.hash(data: Data(expectedRPID.utf8)))
        let hash = data.prefix(32)
        guard Data(hash) == rpHash else {
            throw SecurityError.invalidCredential
        }
        let flags = data[data.startIndex.advanced(by: 32)]
        guard (flags & 0x01) == 0x01, (flags & 0x04) == 0x04 else {
            throw SecurityError.invalidCredential
        }
        let signCount = data.subdata(in: 33..<37).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        if !requireAttestedCredentialData {
            return (signCount, nil, nil)
        }
        guard (flags & 0x40) == 0x40 else {
            throw SecurityError.invalidCredential
        }
        var index = 37 + 16
        let credentialLength = Int(data.subdata(in: index..<(index + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
        index += 2
        let credentialID = data.subdata(in: index..<(index + credentialLength))
        index += credentialLength
        var decoder = WebDashboardCBORDecoder(data: data.subdata(in: index..<data.count))
        let cbor = try decoder.decodeItem()
        guard let coseKey = cbor.mapValue,
              let x = coseKey[int: -2]?.bytesValue,
              let y = coseKey[int: -3]?.bytesValue else {
            throw SecurityError.invalidCredential
        }
        let x963 = Data([0x04]) + x + y
        return (signCount, credentialID, x963)
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension Data {
    init(base64URLString: String) throws {
        let base64 = base64URLString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .padding(toLength: ((base64URLString.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        guard let data = Data(base64Encoded: base64) else {
            throw WebDashboardSecurityController.SecurityError.invalidCredential
        }
        self = data
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct WebDashboardCBOR {
    struct MapValue {
        var entries: [(WebDashboardCBOR, WebDashboardCBOR)]

        subscript(string key: String) -> WebDashboardCBOR? {
            entries.first(where: { $0.0.stringValue == key })?.1
        }

        subscript(int key: Int) -> WebDashboardCBOR? {
            entries.first(where: { $0.0.integerValue == key })?.1
        }
    }

    var integerValue: Int? {
        switch storage {
        case let .unsigned(value): return Int(value)
        case let .negative(value): return value
        default: return nil
        }
    }

    var stringValue: String? {
        if case let .string(value) = storage { return value }
        return nil
    }

    var bytesValue: Data? {
        if case let .bytes(value) = storage { return value }
        return nil
    }

    var mapValue: MapValue? {
        if case let .map(entries) = storage { return MapValue(entries: entries) }
        return nil
    }

    enum Storage {
        case unsigned(UInt64)
        case negative(Int)
        case bytes(Data)
        case string(String)
        case array([WebDashboardCBOR])
        case map([(WebDashboardCBOR, WebDashboardCBOR)])
    }

    var storage: Storage
}

private struct WebDashboardCBORDecoder {
    private let data: Data
    private var index: Data.Index

    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    mutating func decodeItem() throws -> WebDashboardCBOR {
        guard index < data.endIndex else {
            throw WebDashboardSecurityController.SecurityError.invalidCredential
        }
        let initial = data[index]
        index += 1
        let major = initial >> 5
        let info = initial & 0x1f
        switch major {
        case 0:
            return WebDashboardCBOR(storage: .unsigned(try readUInt(info)))
        case 1:
            return WebDashboardCBOR(storage: .negative(-1 - Int(try readUInt(info))))
        case 2:
            let count = Int(try readUInt(info))
            let value = try readData(count)
            return WebDashboardCBOR(storage: .bytes(value))
        case 3:
            let count = Int(try readUInt(info))
            let value = try readData(count)
            guard let string = String(data: value, encoding: .utf8) else {
                throw WebDashboardSecurityController.SecurityError.invalidCredential
            }
            return WebDashboardCBOR(storage: .string(string))
        case 4:
            let count = Int(try readUInt(info))
            let values = try (0..<count).map { _ in try decodeItem() }
            return WebDashboardCBOR(storage: .array(values))
        case 5:
            let count = Int(try readUInt(info))
            let entries = try (0..<count).map { _ in
                (try decodeItem(), try decodeItem())
            }
            return WebDashboardCBOR(storage: .map(entries))
        default:
            throw WebDashboardSecurityController.SecurityError.invalidCredential
        }
    }

    private mutating func readUInt(_ info: UInt8) throws -> UInt64 {
        switch info {
        case 0...23:
            return UInt64(info)
        case 24:
            return UInt64(try readByte())
        case 25:
            return UInt64(try readFixed(UInt16.self))
        case 26:
            return UInt64(try readFixed(UInt32.self))
        case 27:
            return try readFixed(UInt64.self)
        default:
            throw WebDashboardSecurityController.SecurityError.invalidCredential
        }
    }

    private mutating func readByte() throws -> UInt8 {
        guard index < data.endIndex else {
            throw WebDashboardSecurityController.SecurityError.invalidCredential
        }
        let value = data[index]
        index += 1
        return value
    }

    private mutating func readFixed<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let count = MemoryLayout<T>.size
        let value = try readData(count)
        return value.withUnsafeBytes { $0.load(as: T.self).bigEndian }
    }

    private mutating func readData(_ count: Int) throws -> Data {
        guard data.distance(from: index, to: data.endIndex) >= count else {
            throw WebDashboardSecurityController.SecurityError.invalidCredential
        }
        let range = index..<(index + count)
        index += count
        return data.subdata(in: range)
    }
}
