import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRepositoryID: String?
    @State private var showingAddRepositoryWizard = false
    @State private var repositoryPendingDeletion: RepositoryConfiguration?
    @State private var showGlobalSettings = true

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .frame(minWidth: 1120, minHeight: 720)
        .overlay(alignment: .bottomTrailing) {
            if appState.hasUnsavedChanges {
                Button {
                    appState.saveConfiguration()
                } label: {
                    Label("Save Changes", systemImage: "square.and.arrow.down.fill")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                }
                .buttonStyle(GlassActionButtonStyle())
                .padding(.trailing, 24)
                .padding(.bottom, 24)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            }
        }
        .sheet(isPresented: $showingAddRepositoryWizard) {
            AddRepositoryWizard { repository in
                selectedRepositoryID = appState.addRepository(repository)
                appState.saveConfiguration()
            }
            .environmentObject(appState)
        }
        .alert("Delete Repository?", isPresented: deleteAlertBinding, presenting: repositoryPendingDeletion) { repository in
            Button("Delete", role: .destructive) {
                delete(repository: repository)
            }
            Button("Cancel", role: .cancel) {
                repositoryPendingDeletion = nil
            }
        } message: { repository in
            Text("Remove \(repository.name.isEmpty ? repository.id : repository.name) from ShipHook? This only removes it from ShipHook's config.")
        }
        .onAppear {
            if selectedRepositoryID == nil {
                selectedRepositoryID = appState.configuration.repositories.first?.id
            }
        }
        .onChange(of: appState.configuration.repositories) { _, repositories in
            if selectedRepositoryID == nil || !repositories.map(\.id).contains(selectedRepositoryID ?? "") {
                selectedRepositoryID = repositories.first?.id
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Repositories", systemImage: "shippingbox")
                .font(.title2.weight(.bold))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.configuration.repositories, id: \.id) { repo in
                        repositoryRow(repo)
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                showingAddRepositoryWizard = true
            } label: {
                Label("Add Repository", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassActionButtonStyle())
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.blue.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        if let repositoryIndex = selectedRepositoryIndex {
            let repository = appState.configuration.repositories[repositoryIndex]
            let runtimeState = appState.repoStates[repository.id] ?? .initial(id: repository.id)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RepositoryEditor(
                        repository: $appState.configuration.repositories[repositoryIndex],
                        runtimeState: runtimeState,
                        onResetBuildState: {
                            appState.resetBuildState(for: repository.id)
                        },
                        onDeleteRequested: {
                            repositoryPendingDeletion = repository
                        }
                    )
                    globalSettingsPanel
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                stickyHeader(for: repository)
            }
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.cyan.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            ContentUnavailableView(
                "No Repository Selected",
                systemImage: "tray.full",
                description: Text("Add a repository or select one from the sidebar to configure polling, build, and publishing.")
            )
        }
    }

    private func repositoryRow(_ repo: RepositoryConfiguration) -> some View {
        let state = appState.repoStates[repo.id] ?? .initial(id: repo.id)
        let isSelected = selectedRepositoryID == repo.id

        return Button {
            selectedRepositoryID = repo.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: repositoryIcon(for: repo))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.white.opacity(0.18))
                    }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(repo.name.isEmpty ? repo.id : repo.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if state.activity == .building {
                            Text(phaseBadgeLabel(for: state.buildPhase))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }

                    Text("\(repo.owner)/\(repo.repo) @ \(repo.branch)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(state.summary)
                        .font(.caption)
                        .foregroundStyle(color(for: state.activity))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial.opacity(0.45)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? .white.opacity(0.34) : .white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func stickyHeader(for repository: RepositoryConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: repositoryIcon(for: repository))
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name.isEmpty ? repository.id : repository.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("\(repository.owner)/\(repository.repo) @ \(repository.branch)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                headerActionButton("Check Now", systemImage: "arrow.clockwise") {
                    appState.triggerManualPoll()
                }
                headerActionButton("Reload", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                    appState.loadConfiguration()
                }
            }

            if let error = appState.lastGlobalError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var globalSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup(isExpanded: $showGlobalSettings) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        compactField(
                            title: "Poll Interval",
                            symbol: "timer",
                            text: Binding(
                                get: { String(Int(appState.configuration.pollIntervalSeconds)) },
                                set: {
                                    guard let seconds = Double($0) else { return }
                                    appState.configuration.pollIntervalSeconds = seconds
                                }
                            ),
                            prompt: "300"
                        )

                        compactField(
                            title: "GitHub Token Variable",
                            symbol: "key.horizontal",
                            text: optionalStringBinding($appState.configuration.githubTokenEnvVar),
                            prompt: "GITHUB_TOKEN"
                        )
                    }

                    Text("GitHub token is optional for public repositories, recommended for rate limits, and required for private repositories. ShipHook reads the token from the environment variable named above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            } label: {
                Label("Global Settings", systemImage: "slider.horizontal.3")
                    .font(.title3.bold())
            }
        }
        .glassSection()
    }

    private func headerActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 112)
        }
        .buttonStyle(GlassActionButtonStyle())
    }

    private func compactField(title: String, symbol: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for activity: RepositoryActivity) -> Color {
        switch activity {
        case .idle:
            return .secondary
        case .polling:
            return .blue
        case .building:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }

    private func repositoryIcon(for repository: RepositoryConfiguration) -> NSImage {
        if let artifactPath = repository.xcode?.artifactPath {
            let expandedPath = (artifactPath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return NSWorkspace.shared.icon(forFile: expandedPath)
            }
        }

        let checkoutPath = (repository.localCheckoutPath as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: checkoutPath) {
            return NSWorkspace.shared.icon(forFile: checkoutPath)
        }

        if let projectPath = repository.xcode?.projectPath {
            let expandedProjectPath = (projectPath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedProjectPath) {
                return NSWorkspace.shared.icon(forFile: expandedProjectPath)
            }
        }

        if let workspacePath = repository.xcode?.workspacePath {
            let expandedWorkspacePath = (workspacePath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedWorkspacePath) {
                return NSWorkspace.shared.icon(forFile: expandedWorkspacePath)
            }
        }

        if #available(macOS 12.0, *) {
            return NSWorkspace.shared.icon(for: .application)
        }

        return NSWorkspace.shared.icon(forFileType: "app")
    }

    private func phaseBadgeLabel(for phase: RepositoryBuildPhase) -> String {
        switch phase {
        case .idle:
            return "Idle"
        case .queued:
            return "Queued"
        case .syncing:
            return "Syncing"
        case .planningRelease:
            return "Planning"
        case .archiving:
            return "Archiving"
        case .notarizing:
            return "Notarizing"
        case .publishing:
            return "Publishing"
        }
    }

    private var selectedRepositoryIndex: Int? {
        guard let selectedRepositoryID else { return nil }
        return appState.configuration.repositories.firstIndex(where: { $0.id == selectedRepositoryID })
    }

    private func optionalStringBinding(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { repositoryPendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    repositoryPendingDeletion = nil
                }
            }
        )
    }

    private func delete(repository: RepositoryConfiguration) {
        guard let index = appState.configuration.repositories.firstIndex(where: { $0.id == repository.id }) else {
            repositoryPendingDeletion = nil
            return
        }
        appState.removeRepositories(atOffsets: IndexSet(integer: index))
        if selectedRepositoryID == repository.id {
            selectedRepositoryID = appState.configuration.repositories.first?.id
        }
        appState.saveConfiguration()
        repositoryPendingDeletion = nil
    }
}

private struct AddRepositoryWizard: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let onCreate: (RepositoryConfiguration) -> Void

    @State private var localCheckoutPath = ""
    @State private var fallbackOwner = ""
    @State private var fallbackRepo = ""
    @State private var fallbackBranch = "main"
    @State private var inspection: ProjectInspectionResult?
    @State private var releaseInspection: ReleaseInspection?
    @State private var selectedScheme = ""
    @State private var appcastURL = ""
    @State private var autoIncrementBuild = true
    @State private var developmentTeam = ""
    @State private var codeSignIdentity = ""
    @State private var codeSignStyle: SigningConfiguration.CodeSignStyle = .automatic
    @State private var notarizationProfile = ""
    @State private var statusMessage = "Point ShipHook at a local checkout. It will inspect the repo, detect Xcode settings, and generate build/archive/publish defaults."
    @State private var errorMessage: String?
    @State private var isInspecting = false
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Add Repository")
                        .font(.largeTitle.bold())

                    instructionPanel
                    sourcePanel
                    inspectionPanel
                    if let inspection {
                        reviewPanel(inspection: inspection)
                        releasePanel
                        signingPanel
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 760, minHeight: 680)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Repository") {
                        addRepository()
                    }
                    .disabled(inspection == nil || selectedScheme.isEmpty)
                }
            }
        }
    }

    private var instructionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What ShipHook Will Automate")
                .font(.title3.bold())
            Text("1. Poll GitHub for new pushes.\n2. Fetch and check out the new commit in your local repo.\n3. Run `xcodebuild archive` with inferred workspace/project and scheme.\n4. Use the archived signed app directly for Sparkle publishing.\n5. Generate or update the appcast and GitHub release asset.")
            Text("What you still need to do in the target app:")
                .font(.headline)
            Text("Configure the target Xcode project for macOS release signing, ideally with Developer ID Application signing already working in Xcode. ShipHook can drive the build, but it cannot invent valid signing identities for another project.")
                .foregroundStyle(.secondary)
            Text("GitHub token guidance: for public repos this is optional, though recommended to avoid rate limits. For private repos it is required. By default ShipHook looks for a token in `GITHUB_TOKEN`.")
                .foregroundStyle(.secondary)
        }
        .glassSection()
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 1: Local Checkout")
                .font(.title3.bold())
            labeledField("Local Checkout Path", text: $localCheckoutPath)
            Text("Use an existing local clone. ShipHook will inspect this folder and infer owner/repo, branch, Xcode workspace/project, shared schemes, release notes path, archive path, artifact path, and publish command.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("If the repo is private, make sure ShipHook has access to your GitHub token before you rely on polling.")
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup("Fallback values (only used if git metadata is missing)") {
                VStack(alignment: .leading, spacing: 12) {
                    labeledField("Owner", text: $fallbackOwner)
                    labeledField("Repo", text: $fallbackRepo)
                    labeledField("Branch", text: $fallbackBranch)
                }
                .padding(.top, 8)
            }
        }
        .glassSection()
    }

    private var inspectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Step 2: Inspect Project")
                    .font(.title3.bold())
                Spacer()
                Button(isInspecting ? "Inspecting..." : "Inspect Checkout") {
                    inspectCheckout()
                }
                .disabled(localCheckoutPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInspecting)
            }

            Text(statusMessage)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .glassSection()
    }

    private func reviewPanel(inspection: ProjectInspectionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 3: Review Generated Setup")
                .font(.title3.bold())

            if !inspection.schemes.isEmpty {
                Picker("Build Scheme", selection: $selectedScheme) {
                    ForEach(inspection.schemes, id: \.self) { scheme in
                        Text(scheme).tag(scheme)
                    }
                }
                .pickerStyle(.menu)
            }

            Text("ShipHook will archive into `\(suggestedArchivePath)` and publish `\(suggestedArtifactPath)`.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow("GitHub Repo", value: "\(inspection.owner ?? fallbackOwner)/\(inspection.repo ?? fallbackRepo)")
                summaryRow("Branch", value: inspection.branch ?? fallbackBranch)
                summaryRow("Workspace", value: inspection.workspacePath ?? "None")
                summaryRow("Project", value: inspection.projectPath ?? "None")
                summaryRow("Release Notes", value: inspection.releaseNotesPath ?? "None detected")
                summaryRow("App Name", value: selectedScheme)
            }

            DisclosureGroup("Advanced generated settings", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("Publish Command", value: generatedPublishCommand)
                    Text("You can still edit these later in the advanced repository editor after the repo is added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .glassSection()
    }

    private var releasePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 4: Sparkle Versioning")
                .font(.title3.bold())

            labeledField("Appcast URL", text: $appcastURL)
            Toggle("Auto-increment build if appcast build is not newer", isOn: $autoIncrementBuild)

            if let releaseInspection {
                summaryRow("Project Version", value: "\(releaseInspection.projectVersion.marketingVersion) (\(releaseInspection.projectVersion.buildVersion))")
                summaryRow("Latest Appcast Item", value: releaseInspection.latestAppcastItem.map { "\($0.marketingVersion ?? "Unknown") (\($0.buildVersion))" } ?? "No appcast item found")
                summaryRow("Suggested Next Build", value: releaseInspection.suggestedNextBuild)
                Text("ShipHook will compare the target project's current build against the latest appcast item before archiving. If auto-increment is enabled, it will update `CURRENT_PROJECT_VERSION` in the target `.xcodeproj` when needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassSection()
    }

    private var signingPanel: some View {
        SigningOverridesEditor(
            title: "Step 5: Signing Overrides",
            signing: signingConfigurationBinding,
            identities: appState.availableSigningIdentities,
            notarizationProfiles: appState.availableNotarizationProfiles,
            identityLoadError: appState.lastSigningIdentityError,
            diagnostics: appState.signingDiagnostics,
            onRefreshIdentities: appState.refreshSigningIdentities
        )
    }

    private var suggestedArchivePath: String {
        let scheme = selectedScheme.isEmpty ? "App" : selectedScheme.replacingOccurrences(of: " ", with: "-")
        return appState.defaultArchivePath(appName: scheme)
    }

    private var suggestedArtifactPath: String {
        "\(suggestedArchivePath)/Products/Applications/\(selectedScheme).app"
    }

    private var generatedPublishCommand: String {
        """
        bash "$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT" --version "$SHIPHOOK_VERSION" --artifact "$SHIPHOOK_ARTIFACT_PATH" --app-name "\(selectedScheme)" --repo-owner "$SHIPHOOK_GITHUB_OWNER" --repo-name "$SHIPHOOK_GITHUB_REPO" --release-notes "$SHIPHOOK_RELEASE_NOTES_PATH" --docs-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/docs" --releases-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/release-artifacts" --working-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH"
        """
    }

    private func inspectCheckout() {
        isInspecting = true
        errorMessage = nil
        defer { isInspecting = false }

        do {
            let result = try appState.inspectCheckout(localCheckoutPath: localCheckoutPath)
            inspection = result
            selectedScheme = result.suggestedScheme ?? result.schemes.first ?? ""
            let checkoutFolderName = URL(fileURLWithPath: (localCheckoutPath as NSString).expandingTildeInPath).lastPathComponent
            let resolvedOwner = !(result.owner ?? "").isEmpty ? result.owner! : fallbackOwner
            let resolvedRepo = !(result.repo ?? "").isEmpty ? result.repo! : (fallbackRepo.isEmpty ? checkoutFolderName : fallbackRepo)
            let resolvedBranch = !(result.branch ?? "").isEmpty ? result.branch! : fallbackBranch

            if fallbackOwner.isEmpty { fallbackOwner = resolvedOwner }
            if fallbackRepo.isEmpty { fallbackRepo = resolvedRepo }
            if fallbackBranch == "main", !resolvedBranch.isEmpty { fallbackBranch = resolvedBranch }

            appcastURL = appState.defaultAppcastURL(owner: resolvedOwner, repo: resolvedRepo) ?? ""
            let previewRepository = try appState.makeRepositoryFromInspection(
                localCheckoutPath: localCheckoutPath,
                fallbackOwner: resolvedOwner,
                fallbackRepo: resolvedRepo,
                fallbackBranch: resolvedBranch,
                selectedScheme: selectedScheme
            )
            releaseInspection = try appState.inspectReleaseState(for: previewRepository)
            if appcastURL.isEmpty {
                appcastURL = releaseInspection?.appcastURL ?? ""
            }
            applyRecommendedSigningIdentityIfNeeded()
            statusMessage = "Inspection succeeded. ShipHook found your Xcode project and generated default automation settings."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Inspection failed. Fix the checkout path or Xcode project state, then try again."
        }
    }

    private func addRepository() {
        do {
            let generatedRepository = try appState.makeRepositoryFromInspection(
                localCheckoutPath: localCheckoutPath,
                fallbackOwner: fallbackOwner,
                fallbackRepo: fallbackRepo,
                fallbackBranch: fallbackBranch,
                selectedScheme: selectedScheme
            )
            var repository = generatedRepository
            repository.sparkle = SparkleConfiguration(
                appcastURL: appcastURL.isEmpty ? nil : appcastURL,
                autoIncrementBuild: autoIncrementBuild
            )
            repository.signing = SigningConfiguration(
                developmentTeam: developmentTeam.isEmpty ? nil : developmentTeam,
                codeSignIdentity: codeSignIdentity.isEmpty ? nil : codeSignIdentity,
                codeSignStyle: codeSignStyle,
                notarizationProfile: notarizationProfile.isEmpty ? nil : notarizationProfile
            )
            onCreate(repository)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private var signingConfigurationBinding: Binding<SigningConfiguration> {
        Binding(
            get: {
                SigningConfiguration(
                    developmentTeam: developmentTeam.isEmpty ? nil : developmentTeam,
                    codeSignIdentity: codeSignIdentity.isEmpty ? nil : codeSignIdentity,
                    codeSignStyle: codeSignStyle,
                    notarizationProfile: notarizationProfile.isEmpty ? nil : notarizationProfile
                )
            },
            set: { newValue in
                developmentTeam = newValue.developmentTeam ?? ""
                codeSignIdentity = newValue.codeSignIdentity ?? ""
                codeSignStyle = newValue.codeSignStyle
                notarizationProfile = newValue.notarizationProfile ?? ""
            }
        )
    }

    private func applyRecommendedSigningIdentityIfNeeded() {
        guard codeSignIdentity.isEmpty, let identity = appState.availableSigningIdentities.first(where: \.isRecommendedForSparkle) ?? appState.availableSigningIdentities.first else {
            return
        }

        codeSignIdentity = identity.commonName
        if developmentTeam.isEmpty, let teamID = identity.teamID {
            developmentTeam = teamID
        }
    }
}

private struct SigningOverridesEditor: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    @Binding var signing: SigningConfiguration
    let identities: [SigningIdentity]
    let notarizationProfiles: [String]
    let identityLoadError: String?
    let diagnostics: SigningDiagnostics?
    let onRefreshIdentities: () -> Void
    @State private var showDiagnostics = false
    @State private var showingNotaryProfileSheet = false
    @State private var notaryStatusMessage: String?
    @State private var notaryStatusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "checkmark.shield")
                .font(.title3.bold())

            GlassSegmentedControl(
                selection: $signing.codeSignStyle,
                options: [
                    (SigningConfiguration.CodeSignStyle.automatic, "Automatic"),
                    (SigningConfiguration.CodeSignStyle.manual, "Manual")
                ]
            )

            if signing.codeSignStyle == .automatic {
                Text("Automatic is best when the target app already archives correctly in Xcode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Manual signing is for projects that do not already archive with correct release signing settings. For Sparkle, ShipHook expects a `Developer ID Application` certificate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Detected Signing Identity", systemImage: "checkmark.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Detected Signing Identity", selection: selectedIdentityNameBinding) {
                        Text("None Selected").tag("")
                        ForEach(identities) { identity in
                            let suffix = identity.isRecommendedForSparkle ? " Recommended" : ""
                            Text("\(identity.displayName)\(suffix)").tag(identity.commonName)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Spacer()

                Button("Refresh") {
                    onRefreshIdentities()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label(
                    identities.isEmpty
                        ? "No local signing identities detected"
                        : "Detected \(identities.count) local signing identit\(identities.count == 1 ? "y" : "ies")",
                    systemImage: identities.isEmpty ? "xmark.seal" : "checkmark.seal"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            }

            if identities.isEmpty {
                Text("No valid local code-signing identities were found on this Mac. You do not need to upload a `.p12` into ShipHook itself, but you do need the signing certificate and private key installed in this Mac's keychain before manual signing can work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let configuredIdentity = signing.codeSignIdentity, !configuredIdentity.isEmpty,
               configuredIdentity.hasPrefix("Apple Development:") || configuredIdentity.hasPrefix("Mac Development:") {
                Text("`\(configuredIdentity)` is a development certificate. That is not suitable for Sparkle release archives. Use a `Developer ID Application` identity instead.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let identityLoadError {
                Text(identityLoadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            DisclosureGroup(isExpanded: $showDiagnostics) {
                VStack(alignment: .leading, spacing: 8) {
                    if let diagnostics {
                        Text(diagnostics.summary)
                        ForEach(diagnostics.details, id: \.self) { detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("No signing diagnostics available yet.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Signing Diagnostics", systemImage: "stethoscope")
                    .font(.headline)
            }

            HStack(alignment: .top, spacing: 14) {
                labeledField("Development Team", symbol: "person.3", text: developmentTeamBinding)
                labeledField("Code Sign Identity", symbol: "key", text: codeSignIdentityBinding)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Detected Notary Profile", systemImage: "checkmark.seal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Detected Notary Profile", selection: selectedNotaryProfileBinding) {
                        Text("None Selected").tag("")
                        ForEach(notarizationProfiles, id: \.self) { profile in
                            Text(profile).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Spacer()
            }

            if notarizationProfiles.isEmpty {
                Text("No local notary profiles are known to ShipHook yet. Use the setup action below to store one in your keychain on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    showingNotaryProfileSheet = true
                } label: {
                    Label("Set Up Notary Profile", systemImage: "key.badge.exclamationmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(GlassActionButtonStyle())

                if let profile = signing.notarizationProfile, !profile.isEmpty {
                    Text("Using local keychain profile `\(profile)`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let notaryStatusMessage {
                Text(notaryStatusMessage)
                    .font(.caption)
                    .foregroundStyle(notaryStatusIsError ? .red : .green)
            }

            Text("If the certificate is already installed on this Mac, pick it from the menu and ShipHook will fill the fields. The notary profile is just the local keychain profile name that `notarytool` uses on this Mac, not an Apple-side identifier.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassSection()
        .sheet(isPresented: $showingNotaryProfileSheet) {
            NotaryProfileSheet(
                initialProfileName: signing.notarizationProfile ?? "",
                initialTeamID: signing.developmentTeam ?? "",
                onSave: { profileName, appleID, teamID, appSpecificPassword in
                    do {
                        try appState.storeNotarizationProfile(
                            profileName: profileName,
                            appleID: appleID,
                            teamID: teamID,
                            appSpecificPassword: appSpecificPassword
                        )
                        signing.notarizationProfile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if signing.developmentTeam?.isEmpty != false {
                            signing.developmentTeam = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        notaryStatusIsError = false
                        notaryStatusMessage = "Stored notary profile `\(profileName)` in the keychain."
                    } catch {
                        notaryStatusIsError = true
                        notaryStatusMessage = error.localizedDescription
                    }
                }
            )
        }
    }

    private var selectedIdentityNameBinding: Binding<String> {
        Binding(
            get: { signing.codeSignIdentity ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    signing.codeSignIdentity = nil
                    return
                }

                signing.codeSignIdentity = newValue
                if let identity = identities.first(where: { $0.commonName == newValue }),
                   signing.developmentTeam?.isEmpty != false,
                   let teamID = identity.teamID {
                    signing.developmentTeam = teamID
                }
            }
        )
    }

    private var developmentTeamBinding: Binding<String> {
        Binding(
            get: { signing.developmentTeam ?? "" },
            set: { signing.developmentTeam = $0.isEmpty ? nil : $0 }
        )
    }

    private var codeSignIdentityBinding: Binding<String> {
        Binding(
            get: { signing.codeSignIdentity ?? "" },
            set: { signing.codeSignIdentity = $0.isEmpty ? nil : $0 }
        )
    }

    private var notarizationProfileBinding: Binding<String> {
        Binding(
            get: { signing.notarizationProfile ?? "" },
            set: { signing.notarizationProfile = $0.isEmpty ? nil : $0 }
        )
    }

    private var selectedNotaryProfileBinding: Binding<String> {
        Binding(
            get: { signing.notarizationProfile ?? "" },
            set: { newValue in
                signing.notarizationProfile = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func labeledField(_ title: String, symbol: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotaryProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialProfileName: String
    let initialTeamID: String
    let onSave: (String, String, String, String) -> Void

    @State private var profileName = ""
    @State private var appleID = ""
    @State private var teamID = ""
    @State private var appSpecificPassword = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Set Up Notary Profile")
                    .font(.largeTitle.bold())

                Text("ShipHook will store a `notarytool` keychain profile on this Mac so release builds can be notarized and stapled automatically.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Local Profile Name", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Apple ID", text: $appleID)
                        .textFieldStyle(.roundedBorder)
                    TextField("Team ID", text: $teamID)
                        .textFieldStyle(.roundedBorder)
                    SecureField("App-Specific Password", text: $appSpecificPassword)
                        .textFieldStyle(.roundedBorder)
                }

                Text("`Local Profile Name` is only the label saved in this Mac's keychain for `notarytool`. Use an Apple app-specific password here, not your Apple ID account password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 460, minHeight: 320)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Profile") {
                        let trimmedProfileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedAppleID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedTeamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedPassword = appSpecificPassword.trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !trimmedProfileName.isEmpty,
                              !trimmedAppleID.isEmpty,
                              !trimmedTeamID.isEmpty,
                              !trimmedPassword.isEmpty else {
                            errorMessage = "All fields are required."
                            return
                        }

                        onSave(trimmedProfileName, trimmedAppleID, trimmedTeamID, trimmedPassword)
                        dismiss()
                    }
                }
            }
            .onAppear {
                profileName = initialProfileName
                teamID = initialTeamID
            }
        }
    }
}

private struct RepositoryEditor: View {
    @EnvironmentObject private var appState: AppState
    @Binding var repository: RepositoryConfiguration
    let runtimeState: RepositoryRuntimeState
    let onResetBuildState: () -> Void
    let onDeleteRequested: () -> Void
    @State private var showAdvanced = false
    @State private var showLogs = false
    @State private var showRepositoryDetails = true
    @State private var showPaths = false
    @State private var showPublish = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusPanel
            repositoryPanel
            buildSummaryPanel
            sparklePanel
            signingPanel
            publishPanel
            DisclosureGroup("Advanced Build Settings", isExpanded: $showAdvanced) {
                advancedBuildPanel
                    .padding(.top, 12)
            }
            .glassSection()
            deleteAction
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Status", systemImage: "bolt.horizontal.circle")
                    .font(.title3.bold())
                Spacer()
                Text(runtimeState.activity.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            Text(runtimeState.summary)
                .foregroundStyle(primaryStatusTint)

            if runtimeState.activity == .building {
                Label("Current phase: \(buildPhaseLabel)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            if let error = runtimeState.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 18) {
                if let buildStartedAt = runtimeState.buildStartedAt {
                    Label(buildStartedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let logPath = runtimeState.lastLogPath, !logPath.isEmpty {
                    Label(logPath, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !runtimeState.lastLog.isEmpty {
                DisclosureGroup("Recent Output", isExpanded: $showLogs) {
                    ScrollView {
                        Text(runtimeState.lastLog)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 220)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 8)
                }
            }

            if runtimeState.activity == .building {
                Button("Reset Build State") {
                    onResetBuildState()
                }
                .buttonStyle(.bordered)
            }
        }
        .glassSection()
    }

    private var repositoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showRepositoryDetails) {
                VStack(alignment: .leading, spacing: 14) {
                    grid {
                        HStack(alignment: .top, spacing: 14) {
                            labeledField("Display Name", symbol: "character.textbox", text: $repository.name)
                            labeledField("Owner", symbol: "person.crop.circle", text: $repository.owner)
                            labeledField("Repo", symbol: "shippingbox", text: $repository.repo)
                        }

                        HStack(alignment: .top, spacing: 14) {
                            labeledField("Branch", symbol: "point.topleft.down.curvedto.point.bottomright.up", text: $repository.branch)
                            labeledField("Repository ID", symbol: "number", text: $repository.id)
                        }
                    }

                    HStack(spacing: 16) {
                        Toggle("Build on first seen commit", isOn: $repository.buildOnFirstSeen)
                        Spacer()
                    }

                    GlassSegmentedControl(
                        selection: $repository.versionStrategy,
                        options: [
                            (.shortSHA, "Short SHA"),
                            (.shortSHATimestamp, "SHA + Timestamp"),
                            (.dateAndShortSHA, "Date + SHA")
                        ]
                    )

                    DisclosureGroup("Paths & Optional Overrides", isExpanded: $showPaths) {
                        VStack(alignment: .leading, spacing: 14) {
                            labeledField("Local Checkout Path", symbol: "folder", text: $repository.localCheckoutPath)
                            HStack(alignment: .top, spacing: 14) {
                                labeledField("Working Directory", symbol: "terminal", text: optionalStringBinding($repository.workingDirectory))
                                labeledField("Token Env Var", symbol: "key.horizontal", text: optionalStringBinding($repository.githubTokenEnvVar))
                            }
                            labeledField("Release Notes Path", symbol: "note.text", text: optionalStringBinding($repository.releaseNotesPath))
                        }
                        .padding(.top, 10)
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Repository Setup", systemImage: "folder.badge.gearshape")
                    .font(.title3.bold())
            }
        }
        .glassSection()
    }

    private var buildSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Build Automation", systemImage: "hammer")
                .font(.title3.bold())

            switch repository.buildMode {
            case .xcodeArchive:
                let xcode = xcodeBinding
                HStack(alignment: .top, spacing: 14) {
                    labeledField("Scheme", symbol: "shippingbox.circle", text: xcode.scheme)
                    labeledField("App Name", symbol: "app", text: xcode.appName)
                    labeledField("Configuration", symbol: "slider.horizontal.3", text: xcode.configuration)
                }
                HStack(alignment: .top, spacing: 14) {
                    labeledField("Archive Path", symbol: "archivebox", text: xcode.archivePath)
                    labeledField("Artifact Path", symbol: "app.badge", text: xcode.artifactPath)
                }
                Text("ShipHook uses `xcodebuild archive` and publishes the signed `.app` from inside the `.xcarchive`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .shell:
                let shell = shellBinding
                labeledField("Build Command", symbol: "terminal", text: shell.command, axis: .vertical)
                labeledField("Artifact Path", symbol: "app.badge", text: shell.artifactPath)
            }
        }
        .glassSection()
    }

    private var publishPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showPublish) {
                labeledField("Publish Command", symbol: "paperplane", text: $repository.publishCommand, axis: .vertical)
                    .padding(.top, 10)
            } label: {
                Label("Publish", systemImage: "paperplane")
                    .font(.title3.bold())
            }
        }
        .glassSection()
    }

    private var sparklePanel: some View {
        let sparkle = sparkleBinding
        return VStack(alignment: .leading, spacing: 12) {
            Label("Sparkle", systemImage: "sparkles")
                .font(.title3.bold())
            labeledField("Appcast URL", symbol: "link", text: appcastURLBinding)
            Toggle("Auto-increment build when appcast build is not newer", isOn: sparkle.autoIncrementBuild)
            Text("ShipHook compares the latest appcast build with `CURRENT_PROJECT_VERSION` and bumps the project build number before archiving when needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassSection()
    }

    private var signingPanel: some View {
        SigningOverridesEditor(
            title: "Signing Overrides",
            signing: signingBinding,
            identities: appState.availableSigningIdentities,
            notarizationProfiles: appState.availableNotarizationProfiles,
            identityLoadError: appState.lastSigningIdentityError,
            diagnostics: appState.signingDiagnostics,
            onRefreshIdentities: appState.refreshSigningIdentities
        )
    }

    private var deleteAction: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                onDeleteRequested()
            } label: {
                Label("Delete Repository", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
    }

    private var advancedBuildPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSegmentedControl(
                selection: buildModeBinding,
                options: [
                    (.xcodeArchive, "Xcode Archive"),
                    (.shell, "Shell Command")
                ]
            )

            switch repository.buildMode {
            case .xcodeArchive:
                let xcode = xcodeBinding
                grid {
                    HStack(alignment: .top, spacing: 14) {
                        labeledField("Project Path", symbol: "doc.text", text: optionalStringBinding(xcode.projectPath))
                        labeledField("Workspace Path", symbol: "square.grid.2x2", text: optionalStringBinding(xcode.workspacePath))
                    }
                    HStack(alignment: .top, spacing: 14) {
                        labeledField("Scheme", symbol: "shippingbox.circle", text: xcode.scheme)
                        labeledField("App Name", symbol: "app", text: xcode.appName)
                        labeledField("Configuration", symbol: "slider.horizontal.3", text: xcode.configuration)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        labeledField("Archive Path", symbol: "archivebox", text: xcode.archivePath)
                        labeledField("Artifact Path", symbol: "app.badge", text: xcode.artifactPath)
                    }
                }
            case .shell:
                let shell = shellBinding
                labeledField("Build Command", symbol: "terminal", text: shell.command, axis: .vertical)
                labeledField("Artifact Path", symbol: "app.badge", text: shell.artifactPath)
            }
        }
    }

    private var buildModeBinding: Binding<RepositoryConfiguration.BuildMode> {
        Binding(
            get: { repository.buildMode },
            set: { newValue in
                repository.buildMode = newValue
                if newValue == .xcodeArchive && repository.xcode == nil {
                    repository.xcode = .default
                }
                if newValue == .shell && repository.shell == nil {
                    repository.shell = .default
                }
            }
        )
    }

    private var xcodeBinding: Binding<XcodeBuildConfiguration> {
        Binding(
            get: { repository.xcode ?? .default },
            set: { repository.xcode = $0 }
        )
    }

    private var shellBinding: Binding<ShellBuildConfiguration> {
        Binding(
            get: { repository.shell ?? .default },
            set: { repository.shell = $0 }
        )
    }

    private var sparkleBinding: Binding<SparkleConfiguration> {
        Binding(
            get: { repository.sparkle ?? .default },
            set: { repository.sparkle = $0 }
        )
    }

    private var signingBinding: Binding<SigningConfiguration> {
        Binding(
            get: { repository.signing ?? .default },
            set: { repository.signing = $0 }
        )
    }

    private var appcastURLBinding: Binding<String> {
        Binding(
            get: {
                let configuredValue = repository.sparkle?.appcastURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !configuredValue.isEmpty {
                    return configuredValue
                }
                return appState.defaultAppcastURL(owner: repository.owner, repo: repository.repo) ?? ""
            },
            set: { newValue in
                var sparkle = repository.sparkle ?? .default
                sparkle.appcastURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
                repository.sparkle = sparkle
            }
        )
    }

    private var statusColor: Color {
        switch runtimeState.activity {
        case .idle:
            return .secondary
        case .polling:
            return .cyan
        case .building:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }

    private var primaryStatusTint: Color {
        switch runtimeState.activity {
        case .idle:
            return .primary
        case .polling, .building, .succeeded, .failed:
            return statusColor
        }
    }

    private var buildPhaseLabel: String {
        switch runtimeState.buildPhase {
        case .idle:
            return "Idle"
        case .queued:
            return "Queued"
        case .syncing:
            return "Syncing Repository"
        case .planningRelease:
            return "Planning Release"
        case .archiving:
            return "Archiving"
        case .notarizing:
            return "Notarizing"
        case .publishing:
            return "Publishing"
        }
    }

    private func optionalStringBinding(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    @ViewBuilder
    private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
    }

    private func labeledField(_ title: String, symbol: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if axis == .vertical {
                TextField(title, text: text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryGrid(rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.2)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.0)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.1.isEmpty ? "Not set" : row.1)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

private extension View {
    func glassSection() -> some View {
        self
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.1))
            }
            .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }
}

private struct GlassActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(configuration.isPressed ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thickMaterial))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.26 : 0.14))
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.04 : 0.1), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct GlassSegmentedControl<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [(Selection, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.0 == selection

                Text(option.1)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial.opacity(0.32)))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? .white.opacity(0.26) : .white.opacity(0.08))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.18)) {
                            selection = option.0
                        }
                    }
            }
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }
}
