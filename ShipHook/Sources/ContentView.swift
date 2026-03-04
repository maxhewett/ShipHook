import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRepositoryID: String?
    @State private var showingAddRepositoryWizard = false
    @State private var repositoryPendingDeletion: RepositoryConfiguration?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 320, ideal: 344)
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
            clearFieldFocus()
        }
        .onChange(of: appState.configuration.repositories) { _, repositories in
            if selectedRepositoryID == nil || !repositories.map(\.id).contains(selectedRepositoryID ?? "") {
                selectedRepositoryID = repositories.first?.id
            }
        }
        .onChange(of: selectedRepositoryID) { _, _ in
            clearFieldFocus()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Label("Repositories", systemImage: "shippingbox")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    appState.triggerManualPollAll()
                } label: {
                    Label("Check All", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(GlassActionButtonStyle())
                .controlSize(.small)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.configuration.repositories, id: \.id) { repo in
                        repositoryRow(repo)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .scrollClipDisabled()

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
            let repositoryBinding = $appState.configuration.repositories[repositoryIndex]
            let repository = repositoryBinding.wrappedValue
            let runtimeState = appState.repoStates[repository.id] ?? .initial(id: repository.id)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RepositoryEditor(
                        repository: repositoryBinding,
                        runtimeState: runtimeState,
                        onResetBuildState: {
                            appState.resetBuildState(for: repository.id)
                        },
                        onDeleteRequested: {
                            repositoryPendingDeletion = repository
                        }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                stickyHeader(for: repositoryBinding)
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
        let isDisabled = !repo.isEnabled
        let statusColor = isDisabled ? .yellow : color(for: state.activity)
        let statusSymbol = isDisabled ? "xmark.circle.fill" : repositoryStatusSymbol(for: state.activity)
        let latestVersion = appState.displayedVersion(for: repo)

        return Button {
            selectedRepositoryID = repo.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: repositoryIcon(for: repo))
                        .resizable()
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(repo.name.isEmpty ? repo.id : repo.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if isDisabled {
                                Text("Disabled")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(.yellow)
                                    .background(.yellow.opacity(0.16), in: Capsule())
                            }
                            if let latestVersion, !latestVersion.isEmpty {
                                Text("v\(latestVersion)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.thinMaterial, in: Capsule())
                            }
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
                    }

                    Spacer(minLength: 0)
                }

                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        if state.activity == .building && !isDisabled {
                            ProgressView()
                                .controlSize(.small)
                                .tint(statusColor)
                        } else {
                            Image(systemName: statusSymbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor)
                        }
                        Text(isDisabled ? "Disabled" : phaseBadgeLabel(for: state.buildPhase))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14), in: Capsule())

                    Text(state.summary)
                        .lineLimit(2)
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .font(.caption)

                if state.activity == .building && !isDisabled {
                    let progress = phaseProgress(for: state.buildPhase)
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress.current, total: progress.total)
                            .tint(statusColor)
                        Text("Step \(Int(progress.current)) of \(Int(progress.total)) - \(progress.label)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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
            .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func stickyHeader(for repository: Binding<RepositoryConfiguration>) -> some View {
        let value = repository.wrappedValue
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: repositoryIcon(for: value))
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(value.name.isEmpty ? value.id : value.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("\(value.owner)/\(value.repo) @ \(value.branch)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                headerActionButton("Check Now", systemImage: "arrow.clockwise") {
                    appState.triggerManualPoll(for: value.id)
                }
                headerActionButton(value.isEnabled ? "Disable Repo" : "Enable Repo", systemImage: value.isEnabled ? "pause.circle" : "play.circle") {
                    repository.wrappedValue.isEnabled.toggle()
                    appState.saveConfiguration()
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
            return ShipHookLocale.notarising
        case .publishing:
            return "Publishing"
        }
    }

    private func phaseProgress(for phase: RepositoryBuildPhase) -> (current: Double, total: Double, label: String) {
        switch phase {
        case .idle:
            return (0, 5, "Idle")
        case .queued:
            return (0, 5, "Queued")
        case .syncing:
            return (1, 5, "Syncing")
        case .planningRelease:
            return (2, 5, "Planning")
        case .archiving:
            return (3, 5, "Archiving")
        case .notarizing:
            return (4, 5, ShipHookLocale.notarising)
        case .publishing:
            return (5, 5, "Publishing")
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

    private func clearFieldFocus() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
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
    @State private var autoIncrementBuild = false
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
            title: "Step 5: Signing",
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
        bash "$SHIPHOOK_BUNDLED_PUBLISH_SCRIPT" --version "$SHIPHOOK_VERSION" --artifact "$SHIPHOOK_ARTIFACT_PATH" --app-name "\(selectedScheme)" --repo-owner "$SHIPHOOK_GITHUB_OWNER" --repo-name "$SHIPHOOK_GITHUB_REPO" --channel "$SHIPHOOK_RELEASE_CHANNEL" --release-notes "$SHIPHOOK_RELEASE_NOTES_PATH" --docs-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/docs" --releases-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH/release-artifacts" --working-dir "$SHIPHOOK_LOCAL_CHECKOUT_PATH"
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
                autoIncrementBuild: autoIncrementBuild,
                skipIfVersionIsNotNewer: true
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

            if signing.codeSignStyle == .manual {
                Group {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Signing Identity", systemImage: "checkmark.shield")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Signing Identity", selection: selectedIdentityNameBinding) {
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
                                : "\(identities.count) local signing identit\(identities.count == 1 ? "y" : "ies") available",
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

                    HStack(alignment: .top, spacing: 14) {
                        labeledField("Development Team", symbol: "person.3", text: developmentTeamBinding)
                        labeledField("Code Sign Identity", symbol: "key", text: codeSignIdentityBinding)
                    }

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Notary Profile", systemImage: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Notary Profile", selection: selectedNotaryProfileBinding) {
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
                        Label("Set Up Notary Profile", systemImage: "key.fill")
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

                    Text("If the certificate is already installed on this Mac, pick it from the menu and ShipHook will fill the fields. The notary profile is just the local keychain profile name that `notarytool` uses on this Mac, not an Apple-side identifier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
            buildHistoryPanel
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
        let progress = phaseProgress(for: runtimeState.buildPhase)
        let latestBuild = appState.latestBuildRecord(for: repository.id)
        let displayedVersion = appState.displayedVersion(for: repository)
        let statusActivity: RepositoryActivity = repository.isEnabled ? runtimeState.activity : .idle
        let statusText = repository.isEnabled ? runtimeState.activity.rawValue.capitalized : "Disabled"
        let statusIcon = repository.isEnabled ? repositoryStatusSymbol(for: runtimeState.activity) : "xmark.circle.fill"
        let effectiveStatusColor = repository.isEnabled ? statusColor : .yellow
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Status", systemImage: "bolt.horizontal.circle")
                    .font(.title3.bold())
                Spacer()
                HStack(spacing: 8) {
                    if statusActivity == .building {
                        ProgressView()
                            .controlSize(.small)
                            .tint(effectiveStatusColor)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(effectiveStatusColor)
                    }

                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(effectiveStatusColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(effectiveStatusColor.opacity(0.18), in: Capsule())
            }

            Text(runtimeState.summary)
                .foregroundStyle(primaryStatusTint)

            if let latestBuild {
                Label("Current version: \(latestBuild.version)", systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let displayedVersion {
                Label("Published version: \(displayedVersion)", systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if runtimeState.activity == .building {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(statusColor)
                        Text("Step \(Int(progress.current)) of \(Int(progress.total)) - \(progress.label)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor)
                    }

                    ProgressView(value: progress.current, total: progress.total)
                        .tint(statusColor)
                }
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

    private var buildHistoryPanel: some View {
        let history = appState.history(for: repository.id)
        let latestBuild = history.first

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Build History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.title3.bold())
                Spacer()
                if let latestBuild {
                    Text("Current v\(latestBuild.version)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            if history.isEmpty {
                Text("No completed builds yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(history.prefix(6))) { record in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: record.id == latestBuild?.id ? "checkmark.circle.fill" : "clock.fill")
                                .foregroundStyle(record.id == latestBuild?.id ? .green : .secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text("v\(record.version)")
                                        .font(.subheadline.weight(.semibold))
                                    if record.id == latestBuild?.id {
                                        Text("Current")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(.thinMaterial, in: Capsule())
                                    }
                                }

                                Text("Commit \(record.sha.prefix(7))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(record.builtAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
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
                            labeledField("Release Notes Path Override", symbol: "note.text", text: optionalStringBinding($repository.releaseNotesPath))
                            Text("Leave this empty to generate Sparkle release notes from the commit title and description being built.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
        let notifications = notificationBinding
        return VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showPublish) {
                VStack(alignment: .leading, spacing: 14) {
                    labeledField("Publish Command", symbol: "paperplane", text: $repository.publishCommand, axis: .vertical)
                    Divider()
                    Toggle("Post to Discord after successful publish", isOn: notifications.postOnSuccess)
                    Toggle("Post to Discord after failed build", isOn: notifications.postOnFailure)
                    labeledField("Discord Webhook URL", symbol: "message.badge", text: optionalStringBinding(notifications.discordWebhookURL))
                    Text("Discord webhook delivery is best-effort. ShipHook logs webhook failures but does not fail the release after the app is already published.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            Toggle("Skip build when project version is not newer than appcast", isOn: sparkle.skipIfVersionIsNotNewer)
            Toggle("Auto-increment build when appcast build is not newer", isOn: sparkle.autoIncrementBuild)
            Text("ShipHook compares the latest appcast build with `CURRENT_PROJECT_VERSION` and bumps the project build number before archiving when needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassSection()
    }

    private var signingPanel: some View {
        SigningOverridesEditor(
            title: "Signing",
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

    private var notificationBinding: Binding<NotificationConfiguration> {
        Binding(
            get: { repository.notifications ?? .default },
            set: { repository.notifications = $0 }
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
        if !repository.isEnabled {
            return .yellow
        }
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
            return ShipHookLocale.notarising
        case .publishing:
            return "Publishing"
        }
    }

    private func phaseProgress(for phase: RepositoryBuildPhase) -> (current: Double, total: Double, label: String) {
        switch phase {
        case .idle:
            return (0, 5, "Idle")
        case .queued:
            return (0, 5, "Queued")
        case .syncing:
            return (1, 5, "Syncing")
        case .planningRelease:
            return (2, 5, "Planning")
        case .archiving:
            return (3, 5, "Archiving")
        case .notarizing:
            return (4, 5, ShipHookLocale.notarising)
        case .publishing:
            return (5, 5, "Publishing")
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

private func repositoryStatusSymbol(for activity: RepositoryActivity) -> String {
    switch activity {
    case .idle:
        return "pause.circle.fill"
    case .polling:
        return "arrow.clockwise.circle.fill"
    case .building:
        return "gearshape.2.fill"
    case .succeeded:
        return "checkmark.circle.fill"
    case .failed:
        return "xmark.octagon.fill"
    }
}

extension View {
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

struct GlassActionButtonStyle: ButtonStyle {
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

                HStack(spacing: 6) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                    }
                    Text(option.1)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.thinMaterial.opacity(0.22)))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? .white.opacity(0.34) : .white.opacity(0.08))
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
