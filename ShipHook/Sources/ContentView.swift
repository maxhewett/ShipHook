import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var repositoryIconCache = RepositoryIconCache()
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
        .overlay(alignment: .topTrailing) {
            if AppBuildChannel.current == .beta {
                Label("ShipHook Beta", systemImage: "flask.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.orange.opacity(0.35), lineWidth: 1)
                    }
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                    .ignoresSafeArea(.container, edges: .top)
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
                ZStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.cyan.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.72))
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.18), Color.clear],
                        center: .topTrailing,
                        startRadius: 10,
                        endRadius: 420
                    )
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .strokeBorder(.white.opacity(0.06))
            }
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
        let statusColor = isDisabled ? pausedAccentColor : color(for: state.activity)
        let statusSymbol = isDisabled ? "pause.circle.fill" : repositoryStatusSymbol(for: state.activity)
        let latestVersion = appState.displayedVersion(for: repo)
        let latestBuild = appState.latestBuildRecord(for: repo.id)
        let channel = state.releaseChannel ?? latestBuild?.releaseChannel

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
                            if let latestVersion, !latestVersion.isEmpty {
                                Text("v\(latestVersion)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            if channel == .beta {
                                Label("Beta", systemImage: "flask.fill")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(.orange)
                                    .background(.orange.opacity(0.16), in: Capsule())
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
                        Text(isDisabled ? "Paused" : phaseBadgeLabel(for: state.buildPhase))
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
                    let progress = phaseProgress(for: state.buildPhase, detail: state.buildDetail)
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

                headerIconButton(
                    systemImage: "arrow.clockwise",
                    accessibilityLabel: "Check now"
                ) {
                    appState.triggerManualPoll(for: value.id)
                }

                headerIconButton(
                    systemImage: value.isEnabled ? "pause.circle" : "play.circle",
                    accessibilityLabel: value.isEnabled ? "Pause repository" : "Resume repository"
                ) {
                    repository.wrappedValue.isEnabled.toggle()
                    appState.saveConfiguration()
                }

                Spacer()
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

    private func headerIconButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.16))
        }
        .accessibilityLabel(Text(accessibilityLabel))
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
            return .cyan
        case .building:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }

    private var pausedAccentColor: Color {
        .orange
    }

    private func repositoryIcon(for repository: RepositoryConfiguration) -> NSImage {
        repositoryIconCache.icon(for: repository)
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

    private func phaseProgress(for phase: RepositoryBuildPhase, detail: String?) -> (current: Double, total: Double, label: String) {
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
            return (3, 5, detail ?? "Archiving")
        case .notarizing:
            return (4, 5, detail ?? ShipHookLocale.notarising)
        case .publishing:
            return (5, 5, detail ?? "Publishing")
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

private final class RepositoryIconCache: ObservableObject {
    private let cache = NSCache<NSString, NSImage>()

    func icon(for repository: RepositoryConfiguration) -> NSImage {
        let key = cacheKey(for: repository)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let icon = resolveIcon(for: repository)
        cache.setObject(icon, forKey: key as NSString)
        return icon
    }

    private func cacheKey(for repository: RepositoryConfiguration) -> String {
        [
            repository.id,
            repository.localCheckoutPath,
            repository.xcode?.artifactPath ?? "",
            repository.xcode?.projectPath ?? "",
            repository.xcode?.workspacePath ?? "",
        ].joined(separator: "|")
    }

    private func resolveIcon(for repository: RepositoryConfiguration) -> NSImage {
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
    @State private var selectedSigningIdentity = ""
    @State private var selectedDevelopmentTeam = ""
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
                skipIfVersionIsNotNewer: true,
                betaIconPath: nil
            )
            repository.signing = SigningConfiguration(
                developmentTeam: selectedDevelopmentTeam.isEmpty ? nil : selectedDevelopmentTeam,
                codeSignIdentity: selectedSigningIdentity.isEmpty ? nil : selectedSigningIdentity,
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
                    developmentTeam: selectedDevelopmentTeam.isEmpty ? nil : selectedDevelopmentTeam,
                    codeSignIdentity: selectedSigningIdentity.isEmpty ? nil : selectedSigningIdentity,
                    codeSignStyle: codeSignStyle,
                    notarizationProfile: notarizationProfile.isEmpty ? nil : notarizationProfile
                )
            },
            set: { newValue in
                selectedDevelopmentTeam = newValue.developmentTeam ?? ""
                selectedSigningIdentity = newValue.codeSignIdentity ?? ""
                codeSignStyle = newValue.codeSignStyle
                notarizationProfile = newValue.notarizationProfile ?? ""
            }
        )
    }

    private func applyRecommendedSigningIdentityIfNeeded() {
        guard let identity = appState.availableSigningIdentities.first(where: \.isRecommendedForSparkle) ?? appState.availableSigningIdentities.first else {
            return
        }
        // Preload wizard signing config so manual mode has sensible defaults.
        var config = signingConfigurationBinding.wrappedValue
        config.codeSignIdentity = identity.commonName
        config.developmentTeam = identity.teamID
        signingConfigurationBinding.wrappedValue = config
        selectedSigningIdentity = identity.commonName
        selectedDevelopmentTeam = identity.teamID ?? ""
    }
}

private struct SigningOverridesEditor: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    @Binding var signing: SigningConfiguration
    let identities: [SigningIdentity]
    let notarizationProfiles: [String]
    let onRefreshIdentities: () -> Void
    @State private var showingNotaryProfileSheet = false
    @State private var notaryStatusMessage: String?
    @State private var notaryStatusIsError = false
    @State private var showSigningConfiguration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "checkmark.shield")
                    .font(.title3.bold())
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showSigningConfiguration.toggle()
                    }
                } label: {
                    Label(showSigningConfiguration ? "Done" : "Configure", systemImage: showSigningConfiguration ? "checkmark.circle.fill" : "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(showSigningConfiguration ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                if showSigningConfiguration {
                    VStack(alignment: .leading, spacing: 12) {
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
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Mode")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(signing.codeSignStyle == .automatic ? "Automatic" : "Manual")
                                .font(.subheadline.weight(.semibold))
                        }
                        if let identity = signing.codeSignIdentity, !identity.isEmpty {
                            HStack(spacing: 8) {
                                Text("Identity")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(identity)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        if let profile = signing.notarizationProfile, !profile.isEmpty {
                            HStack(spacing: 8) {
                                Text("Notary")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(profile)
                                    .font(.caption)
                            }
                        }
                        Text("Tap configure to edit signing identity and notarisation profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .rotation3DEffect(.degrees(showSigningConfiguration ? 2 : 0), axis: (x: 0, y: 1, z: 0))
            .frame(minHeight: 120, alignment: .topLeading)
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
                    signing.developmentTeam = nil
                    return
                }

                signing.codeSignIdentity = newValue
                if let identity = identities.first(where: { $0.commonName == newValue }),
                   let teamID = identity.teamID {
                    signing.developmentTeam = teamID
                }
            }
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
    private enum EditorTab: Hashable {
        case status
        case builds
        case configuration
    }

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @Binding var repository: RepositoryConfiguration
    let runtimeState: RepositoryRuntimeState
    let onResetBuildState: () -> Void
    let onDeleteRequested: () -> Void
    @State private var showAdvanced = false
    @State private var showRepositoryDetails = true
    @State private var showPaths = false
    @State private var showWebhooks = false
    @State private var showBuildAutomation = false
    @State private var showSparkleSettings = false
    @State private var showRepositorySetup = false
    @State private var selectedTab: EditorTab = .status
    @State private var betaIconSelectionError: String?
    @State private var rollbackCandidate: GitHubReleaseSummary?
    @State private var showReleaseExplorerManager = false
    @State private var releaseExplorerPage = 0
    @State private var releaseDetailsCandidate: GitHubReleaseSummary?
    @State private var managerReleaseDetailsCandidate: GitHubReleaseSummary?
    @State private var showBuildExplorer = false
    @State private var buildExplorerPage = 0
    @State private var buildDetailsCandidate: BuildRecord?
    @State private var managerBuildDetailsCandidate: BuildRecord?
    @State private var followLogOutput = true
    @State private var copiedLogToastVisible = false

    private let logBottomAnchorID = "shiphook-log-bottom-anchor"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSegmentedControl(
                selection: $selectedTab,
                options: [
                    (.status, "Status"),
                    (.builds, "Builds & Releases"),
                    (.configuration, "Configuration")
                ]
            )

            LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 14) {
                switch selectedTab {
                case .status:
                    statusPanel
                    activityLogPanel
                case .builds:
                    buildHistoryPanel
                    releaseExplorerPanel
                case .configuration:
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
        }
        .onAppear {
            appState.refreshReleaseExplorer(for: repository.id, force: false)
            appState.preloadBuildCommitAuthors(for: repository.id)
        }
        .overlay(alignment: .bottomTrailing) {
            if copiedLogToastVisible {
                Label("Copied Output", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thickMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.14))
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Rollback Release", isPresented: Binding(
            get: { rollbackCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    rollbackCandidate = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                rollbackCandidate = nil
            }
            Button("Rollback", role: .destructive) {
                guard let rollbackCandidate else { return }
                appState.rollbackRelease(repositoryID: repository.id, release: rollbackCandidate)
                self.rollbackCandidate = nil
            }
        } message: {
            if let rollbackCandidate {
                Text("This will remove \(rollbackCandidate.tagName) from the \(rollbackCandidate.isBeta ? "beta" : "stable") appcast, push the appcast change, and delete the GitHub release/tag.")
            } else {
                Text("This action cannot be undone.")
            }
        }
        .sheet(isPresented: $showReleaseExplorerManager) {
            releaseExplorerManagerSheet
        }
        .sheet(item: $releaseDetailsCandidate) { release in
            releaseDetailsSheet(for: release)
        }
        .sheet(isPresented: $showBuildExplorer) {
            buildExplorerSheet
        }
        .sheet(item: $buildDetailsCandidate) { record in
            buildDetailsSheet(for: record)
        }
    }

    private var cardColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 420, maximum: 760), spacing: 14, alignment: .top)
        ]
    }

    private var statusPanel: some View {
        let progress = phaseProgress(for: runtimeState.buildPhase, detail: runtimeState.buildDetail)
        let latestBuild = appState.latestBuildRecord(for: repository.id)
        let displayedVersion = appState.displayedVersion(for: repository)
        let releaseChannel = runtimeState.releaseChannel ?? latestBuild?.releaseChannel
        let statusActivity: RepositoryActivity = repository.isEnabled ? runtimeState.activity : .idle
        let statusText = repository.isEnabled ? runtimeState.activity.rawValue.capitalized : "Paused"
        let statusIcon = repository.isEnabled ? repositoryStatusSymbol(for: runtimeState.activity) : "pause.circle.fill"
        let effectiveStatusColor = repository.isEnabled ? statusColor : pausedAccentColor
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

            if let authorLogin = runtimeState.lastCommitAuthorLogin, !authorLogin.isEmpty {
                HStack(spacing: 8) {
                    if let avatarURL = runtimeState.lastCommitAuthorAvatarURL {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Circle()
                                    .fill(.thinMaterial)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                    }

                    if let profileURL = runtimeState.lastCommitAuthorProfileURL {
                        Link("@\(authorLogin)", destination: profileURL)
                            .font(.caption.weight(.semibold))
                    } else {
                        Text("@\(authorLogin)")
                            .font(.caption.weight(.semibold))
                    }
                    Text("published this commit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let latestBuild {
                Label("Current version: \(latestBuild.version)", systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let displayedVersion {
                Label("Published version: \(displayedVersion)", systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if releaseChannel == .beta {
                Label("Channel: Beta", systemImage: "flask.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Label("Channel: Stable", systemImage: "checkmark.seal")
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

            if runtimeState.activity == .building {
                Button("Reset Build State") {
                    onResetBuildState()
                }
                .buttonStyle(.bordered)
            }
        }
        .glassSection()
    }

    private var activityLogPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live Output", systemImage: "text.alignleft")
                    .font(.title3.bold())
                Spacer()
                Button {
                    followLogOutput.toggle()
                } label: {
                    Label(followLogOutput ? "Live" : "Paused", systemImage: followLogOutput ? "play.circle.fill" : "pause.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    copyLatestLogToPasteboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(runtimeState.lastLog.isEmpty)
            }

            if runtimeState.lastLog.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No output yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(.regularMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(runtimeState.lastLog)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(12)
                            Color.clear
                                .frame(height: 1)
                                .id(logBottomAnchorID)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                    .background(.regularMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onAppear {
                        guard followLogOutput else { return }
                        scrollLogToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: runtimeState.lastLog) { _, _ in
                        guard followLogOutput else { return }
                        scrollLogToBottom(proxy: proxy, animated: true)
                    }
                }
            }

            if let logPath = runtimeState.lastLogPath, !logPath.isEmpty {
                Text(logPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
        }
        .glassSection()
    }

    private var buildHistoryPanel: some View {
        let history = appState.history(for: repository.id)
        let latestBuild = history.first
        let previewBuilds = Array(history.prefix(2))
        let remainingCount = max(0, history.count - previewBuilds.count)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Build History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.title3.bold())
                Spacer()
                if let latestBuild {
                    HStack(spacing: 8) {
                        Text("Current v\(latestBuild.version)")
                            .font(.caption.weight(.semibold))
                        if latestBuild.releaseChannel == .beta {
                            Label("Beta", systemImage: "flask.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
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
                    ForEach(previewBuilds) { record in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: record.id == latestBuild?.id ? "checkmark.circle.fill" : "clock.fill")
                                .foregroundStyle(record.id == latestBuild?.id ? .green : .secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text("v\(record.version)")
                                        .font(.subheadline.weight(.semibold))
                                    if record.releaseChannel == .beta {
                                        Label("Beta", systemImage: "flask.fill")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                    }
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

                                buildAuthorLine(for: record)
                            }

                            Spacer()

                            Button {
                                buildDetailsCandidate = record
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if remainingCount > 0 {
                        Text("\(remainingCount) more build\(remainingCount == 1 ? "" : "s").")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        Button {
                            buildExplorerPage = 0
                            managerBuildDetailsCandidate = nil
                            showBuildExplorer = true
                        } label: {
                            Label("Explore Builds", systemImage: "rectangle.stack")
                        }
                        .buttonStyle(GlassActionButtonStyle())
                    }
                }
            }
        }
        .glassSection()
        .onAppear {
            appState.preloadBuildCommitAuthors(for: repository.id)
        }
    }

    private var releaseExplorerPanel: some View {
        let releases = appState.releasesByRepository[repository.id] ?? []
        let isLoading = appState.releaseExplorerLoadingRepositoryIDs.contains(repository.id)
        let error = appState.releaseExplorerErrors[repository.id]
        let lastRefreshed = appState.releaseExplorerLastRefreshedAt[repository.id]
        let previewReleases = Array(releases.prefix(2))
        let remainingCount = max(0, releases.count - previewReleases.count)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Release Explorer", systemImage: "shippingbox.and.arrow.backward")
                    .font(.title3.bold())
                Spacer()
                Text(releaseExplorerRefreshLabel(from: lastRefreshed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    appState.refreshReleaseExplorer(for: repository.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(0.14))
                }
                .disabled(isLoading)
            }

            if let error, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isLoading && releases.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading releases...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if releases.isEmpty {
                Text("No releases found yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(previewReleases) { release in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: release.isBeta ? "flask.fill" : "checkmark.seal.fill")
                                .foregroundStyle(release.isBeta ? .orange : .green)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(release.tagName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(release.isBeta ? "Beta" : "Stable")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background((release.isBeta ? Color.orange : Color.green).opacity(0.15), in: Capsule())
                                        .foregroundStyle(release.isBeta ? .orange : .green)
                                }

                                Text(release.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if let publishedAt = release.publishedAt {
                                    Text(publishedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                releaseAuthorLine(for: release)
                            }

                            Spacer()

                            Button {
                                releaseDetailsCandidate = release
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if remainingCount > 0 {
                        Text("\(remainingCount) more release\(remainingCount == 1 ? "" : "s").")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        Button {
                            releaseExplorerPage = 0
                            managerReleaseDetailsCandidate = nil
                            showReleaseExplorerManager = true
                        } label: {
                            Label("Explore Releases", systemImage: "rectangle.stack")
                        }
                        .buttonStyle(GlassActionButtonStyle())
                    }
                }
            }
        }
        .glassSection()
    }

    private var repositoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Repository Setup", systemImage: "folder.badge.gearshape")
                    .font(.title3.bold())
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showRepositorySetup.toggle()
                    }
                } label: {
                    Label(showRepositorySetup ? "Done" : "Configure", systemImage: showRepositorySetup ? "checkmark.circle.fill" : "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(showRepositorySetup ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                if showRepositorySetup {
                    VStack(alignment: .leading, spacing: 14) {
                        grid {
                            HStack(alignment: .top, spacing: 14) {
                                labeledField("Display Name", symbol: "character.textbox", text: $repository.name)
                                labeledField("Owner", symbol: "person.crop.circle", text: $repository.owner)
                                labeledField("Repo", symbol: "shippingbox", text: $repository.repo)
                            }

                            HStack(alignment: .top, spacing: 14) {
                                labeledField("Branch", symbol: "point.topleft.down.curvedto.point.bottomright.up", text: $repository.branch)
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
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    summaryGrid(rows: [
                        ("Repository", "\(repository.owner)/\(repository.repo)", "shippingbox"),
                        ("Branch", repository.branch, "point.topleft.down.curvedto.point.bottomright.up"),
                        ("Checkout", repository.localCheckoutPath, "folder")
                    ])
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .rotation3DEffect(.degrees(showRepositorySetup ? -2 : 0), axis: (x: 0, y: 1, z: 0))
            .frame(minHeight: 120, alignment: .topLeading)
        }
        .glassSection()
    }

    private var buildSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Build Automation", systemImage: "hammer")
                    .font(.title3.bold())
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showBuildAutomation.toggle()
                    }
                } label: {
                    Label(showBuildAutomation ? "Done" : "Configure", systemImage: showBuildAutomation ? "checkmark.circle.fill" : "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(showBuildAutomation ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                if showBuildAutomation {
                    VStack(alignment: .leading, spacing: 12) {
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
                        case .shell:
                            let shell = shellBinding
                            labeledField("Build Command", symbol: "terminal", text: shell.command, axis: .vertical)
                            labeledField("Artifact Path", symbol: "app.badge", text: shell.artifactPath)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        switch repository.buildMode {
                        case .xcodeArchive:
                            let xcode = xcodeBinding
                            summaryGrid(rows: [
                                ("Scheme", xcode.wrappedValue.scheme, "shippingbox.circle"),
                                ("App Name", xcode.wrappedValue.appName, "app"),
                                ("Configuration", xcode.wrappedValue.configuration, "slider.horizontal.3")
                            ])
                        case .shell:
                            let shell = shellBinding.wrappedValue
                            summaryGrid(rows: [
                                ("Build Command", shell.command, "terminal"),
                                ("Artifact Path", shell.artifactPath, "app.badge")
                            ])
                        }
                        Text("Tap the configure icon to edit build settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .rotation3DEffect(.degrees(showBuildAutomation ? 2 : 0), axis: (x: 0, y: 1, z: 0))
            .frame(minHeight: 130, alignment: .topLeading)
        }
        .glassSection()
    }

    private var publishPanel: some View {
        let notifications = notificationBinding
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Webhooks", systemImage: "message.badge")
                    .font(.title3.bold())
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showWebhooks.toggle()
                    }
                } label: {
                    Label(showWebhooks ? "Done" : "Configure", systemImage: showWebhooks ? "checkmark.circle.fill" : "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(showWebhooks ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                if showWebhooks {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Post to Discord after successful publish", isOn: notifications.postOnSuccess)
                        Toggle("Post to Discord after failed build", isOn: notifications.postOnFailure)
                        labeledField("Discord Webhook URL", symbol: "message.badge", text: optionalStringBinding(notifications.discordWebhookURL))
                        Text("Discord webhook delivery is best-effort. ShipHook logs webhook failures but does not fail the release after the app is already published.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    summaryGrid(rows: [
                        ("Success Notifications", notifications.wrappedValue.postOnSuccess ? "Enabled" : "Disabled", "checkmark.circle"),
                        ("Failure Notifications", notifications.wrappedValue.postOnFailure ? "Enabled" : "Disabled", "xmark.circle"),
                        ("Webhook URL", notifications.wrappedValue.discordWebhookURL ?? "", "message.badge")
                    ])
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .rotation3DEffect(.degrees(showWebhooks ? 2 : 0), axis: (x: 0, y: 1, z: 0))
            .frame(minHeight: 120, alignment: .topLeading)
        }
        .glassSection()
    }

    private var sparklePanel: some View {
        let sparkle = sparkleBinding
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Sparkle", systemImage: "sparkles")
                    .font(.title3.bold())
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showSparkleSettings.toggle()
                    }
                } label: {
                    Label(showSparkleSettings ? "Done" : "Configure", systemImage: showSparkleSettings ? "checkmark.circle.fill" : "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(showSparkleSettings ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            ZStack {
                if showSparkleSettings {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledField("Appcast URL", symbol: "link", text: appcastURLBinding)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Beta Icon Path (.icon or .icns)", systemImage: "photo.badge.plus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(alignment: .center, spacing: 10) {
                                TextField("Path to beta icon", text: optionalStringBinding(sparkle.betaIconPath))
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse") {
                                    chooseBetaIcon()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        Toggle("Skip build when project version is not newer than appcast", isOn: sparkle.skipIfVersionIsNotNewer)
                        Toggle("Auto-increment build when appcast build is not newer", isOn: sparkle.autoIncrementBuild)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        summaryGrid(rows: [
                            ("Appcast", appcastURLBinding.wrappedValue, "link"),
                            ("Skip Older Versions", sparkle.wrappedValue.skipIfVersionIsNotNewer ? "Enabled" : "Disabled", "arrow.uturn.backward.circle"),
                            ("Auto Increment Build", sparkle.wrappedValue.autoIncrementBuild ? "Enabled" : "Disabled", "number.circle")
                        ])
                        Text("Tap the configure icon to edit Sparkle settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .rotation3DEffect(.degrees(showSparkleSettings ? -2 : 0), axis: (x: 0, y: 1, z: 0))
            .frame(minHeight: 130, alignment: .topLeading)

            if let betaIconSelectionError, !betaIconSelectionError.isEmpty {
                Label(betaIconSelectionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .glassSection()
    }

    private var signingPanel: some View {
        SigningOverridesEditor(
            title: "Signing",
            signing: signingBinding,
            identities: appState.availableSigningIdentities,
            notarizationProfiles: appState.availableNotarizationProfiles,
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
            return pausedAccentColor
        }
        switch runtimeState.activity {
        case .idle:
            return .primary
        case .polling, .building, .succeeded, .failed:
            return statusColor
        }
    }

    private var pausedAccentColor: Color {
        .orange
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

    private func phaseProgress(for phase: RepositoryBuildPhase, detail: String?) -> (current: Double, total: Double, label: String) {
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
            return (3, 5, detail ?? "Archiving")
        case .notarizing:
            return (4, 5, detail ?? ShipHookLocale.notarising)
        case .publishing:
            return (5, 5, detail ?? "Publishing")
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

    private func chooseBetaIcon() {
        let requiresIconComposer = usesIconComposerProject
        let allowedExtensions = requiresIconComposer ? ["icon"] : ["icon", "icns"]

        let panel = NSOpenPanel()
        panel.title = "Choose Beta Icon"
        panel.message = requiresIconComposer
            ? "This project uses Icon Composer. Select a .icon file for beta builds."
            : "Select a .icon or .icns file to use for beta builds."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = allowedExtensions
        panel.allowsOtherFileTypes = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            betaIconSelectionError = requiresIconComposer
                ? "This repository requires a .icon file."
                : "Please choose a .icon or .icns file."
            return
        }

        var sparkleConfiguration = repository.sparkle ?? .default
        sparkleConfiguration.betaIconPath = url.path
        repository.sparkle = sparkleConfiguration
        betaIconSelectionError = nil
    }

    private func copyLatestLogToPasteboard() {
        guard !runtimeState.lastLog.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(runtimeState.lastLog, forType: .string)
        withAnimation(.snappy(duration: 0.16)) {
            copiedLogToastVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(.snappy(duration: 0.2)) {
                copiedLogToastVisible = false
            }
        }
    }

    private func scrollLogToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(logBottomAnchorID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.16)) {
                action()
            }
        } else {
            action()
        }
    }

    private var usesIconComposerProject: Bool {
        guard repository.buildMode == .xcodeArchive else {
            return false
        }

        if let projectPath = repository.xcode?.projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectPath.isEmpty {
            let pbxprojPath = (projectPath as NSString).expandingTildeInPath + "/project.pbxproj"
            if let text = try? String(contentsOfFile: pbxprojPath, encoding: .utf8),
               text.contains("folder.iconcomposer.icon") {
                return true
            }
        }

        let checkoutPath = (repository.localCheckoutPath as NSString).expandingTildeInPath
        guard !checkoutPath.isEmpty,
              let enumerator = FileManager.default.enumerator(atPath: checkoutPath) else {
            return false
        }

        for case let relativePath as String in enumerator {
            guard relativePath.hasSuffix(".xcodeproj/project.pbxproj") else {
                continue
            }
            let fullPath = "\(checkoutPath)/\(relativePath)"
            if let text = try? String(contentsOfFile: fullPath, encoding: .utf8),
               text.contains("folder.iconcomposer.icon") {
                return true
            }
        }

        if containsIconComposerAsset(under: checkoutPath) {
            return true
        }

        return false
    }

    private func containsIconComposerAsset(under rootPath: String) -> Bool {
        guard !rootPath.isEmpty,
              let enumerator = FileManager.default.enumerator(atPath: rootPath) else {
            return false
        }

        for case let relativePath as String in enumerator {
            if relativePath.lowercased().hasSuffix(".icon") {
                return true
            }
        }

        return false
    }

    private var buildExplorerSheet: some View {
        let history = appState.history(for: repository.id)
        let pageSize = 10
        let totalPages = max(1, Int(ceil(Double(max(history.count, 1)) / Double(pageSize))))
        let currentPage = min(max(0, buildExplorerPage), totalPages - 1)
        let start = currentPage * pageSize
        let end = min(start + pageSize, history.count)
        let pageBuilds = start < end ? Array(history[start..<end]) : []

        return NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Build History Explorer", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.title2.bold())
                    Spacer()
                    Button("Done") {
                        showBuildExplorer = false
                    }
                    .keyboardShortcut(.cancelAction)
                }

                if pageBuilds.isEmpty {
                    Text("No completed builds yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(pageBuilds) { record in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: record.id == history.first?.id ? "checkmark.circle.fill" : "clock.fill")
                                        .foregroundStyle(record.id == history.first?.id ? .green : .secondary)
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text("v\(record.version)")
                                                .font(.subheadline.weight(.semibold))
                                            if record.releaseChannel == .beta {
                                                Text("Beta")
                                                    .font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .foregroundStyle(.orange)
                                                    .background(.orange.opacity(0.15), in: Capsule())
                                            }
                                            if record.id == history.first?.id {
                                                Text("Current")
                                                    .font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(.thinMaterial, in: Capsule())
                                            }
                                        }

                                        Text("Commit \(record.sha.prefix(7))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(record.builtAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        buildAuthorLine(for: record)
                                    }

                                    Spacer()

                                    HStack(spacing: 8) {
                                        Button {
                                            managerBuildDetailsCandidate = record
                                        } label: {
                                            Image(systemName: "info.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)

                                        if let logPath = record.logPath, !logPath.isEmpty {
                                            Button {
                                                revealLog(at: logPath)
                                            } label: {
                                                Label("Log", systemImage: "doc.text.magnifyingglass")
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }

                HStack {
                    Text("Page \(currentPage + 1) of \(totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Previous") {
                        buildExplorerPage = max(0, currentPage - 1)
                    }
                    .disabled(currentPage == 0)
                    Button("Next") {
                        buildExplorerPage = min(totalPages - 1, currentPage + 1)
                    }
                    .disabled(currentPage >= totalPages - 1)
                }
            }
            .padding(18)
            .frame(minWidth: 760, minHeight: 520)
            .sheet(item: $managerBuildDetailsCandidate) { record in
                buildDetailsSheet(for: record)
            }
        }
    }

    private var releaseExplorerManagerSheet: some View {
        let releases = appState.releasesByRepository[repository.id] ?? []
        let pageSize = 10
        let totalPages = max(1, Int(ceil(Double(max(releases.count, 1)) / Double(pageSize))))
        let currentPage = min(max(0, releaseExplorerPage), totalPages - 1)
        let start = currentPage * pageSize
        let end = min(start + pageSize, releases.count)
        let pageReleases = start < end ? Array(releases[start..<end]) : []
        let isLoading = appState.releaseExplorerLoadingRepositoryIDs.contains(repository.id)
        let error = appState.releaseExplorerErrors[repository.id]
        let lastRefreshed = appState.releaseExplorerLastRefreshedAt[repository.id]

        return NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Release Explorer", systemImage: "shippingbox.and.arrow.backward")
                        .font(.title2.bold())
                    Spacer()
                    Text(releaseExplorerRefreshLabel(from: lastRefreshed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        appState.refreshReleaseExplorer(for: repository.id)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                        .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                    Button("Done") {
                        showReleaseExplorerManager = false
                    }
                    .keyboardShortcut(.cancelAction)
                }

                if let error, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if pageReleases.isEmpty {
                    VStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                        }
                        Text(isLoading ? "Loading releases..." : "No releases found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(pageReleases) { release in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: release.isBeta ? "flask.fill" : "checkmark.seal.fill")
                                        .foregroundStyle(release.isBeta ? .orange : .green)
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(release.tagName)
                                                .font(.subheadline.weight(.semibold))
                                            Text(release.isBeta ? "Beta" : "Stable")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background((release.isBeta ? Color.orange : Color.green).opacity(0.15), in: Capsule())
                                                .foregroundStyle(release.isBeta ? .orange : .green)
                                        }

                                        Text(release.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        if let publishedAt = release.publishedAt {
                                            Text(publishedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        releaseAuthorLine(for: release)
                                    }

                                    Spacer()

                                    HStack(spacing: 8) {
                                        Button {
                                            managerReleaseDetailsCandidate = release
                                        } label: {
                                            Image(systemName: "info.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)

                                        Button(role: .destructive) {
                                            rollbackCandidate = release
                                        } label: {
                                            Label("Rollback", systemImage: "arrow.uturn.backward.circle")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(isLoading)
                                    }
                                }
                                .padding(10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }

                HStack {
                    Text("Page \(currentPage + 1) of \(totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Previous") {
                        releaseExplorerPage = max(0, currentPage - 1)
                    }
                    .disabled(currentPage == 0 || isLoading)
                    Button("Next") {
                        releaseExplorerPage = min(totalPages - 1, currentPage + 1)
                    }
                    .disabled(currentPage >= totalPages - 1 || isLoading)
                }
            }
            .padding(18)
            .frame(minWidth: 760, minHeight: 520)
            .sheet(item: $managerReleaseDetailsCandidate) { release in
                releaseDetailsSheet(for: release)
            }
        }
    }

    private func releaseDetailsSheet(for release: GitHubReleaseSummary) -> some View {
        let releases = appState.releasesByRepository[repository.id] ?? []
        let compareURL = compareURL(for: release, in: releases)
        let notes = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let closeDetails: () -> Void = {
            releaseDetailsCandidate = nil
            managerReleaseDetailsCandidate = nil
        }

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let publishedAt = release.publishedAt {
                        Text("Published \(publishedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Release Notes")
                            .font(.headline)
                        renderedReleaseNotesView(for: notes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSection()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Diff Report")
                            .font(.headline)
                        if let compareURL {
                            Link(destination: compareURL) {
                                Label("Open GitHub Compare", systemImage: "arrow.triangle.branch")
                            }
                            .font(.subheadline.weight(.semibold))
                        } else {
                            Text("No previous release to compare against.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let htmlURL = release.htmlURL {
                            Link(destination: htmlURL) {
                                Label("Open GitHub Release", systemImage: "link")
                            }
                            .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSection()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 620, minHeight: 460)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Label(release.tagName, systemImage: release.isBeta ? "flask.fill" : "checkmark.seal.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(release.isBeta ? .orange : .green)
                    Text(release.isBeta ? "Beta" : "Stable")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((release.isBeta ? Color.orange : Color.green).opacity(0.15), in: Capsule())
                        .foregroundStyle(release.isBeta ? .orange : .green)
                    Spacer()
                    Button("Done") {
                        closeDetails()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func buildDetailsSheet(for record: BuildRecord) -> some View {
        let closeDetails: () -> Void = {
            buildDetailsCandidate = nil
            managerBuildDetailsCandidate = nil
        }
        let commitURL = URL(string: "https://github.com/\(repository.owner)/\(repository.repo)/commit/\(record.sha)")

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Built \(record.builtAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build Metadata")
                            .font(.headline)

                        metadataRow(title: "Version", value: record.version)
                        metadataRow(title: "Commit", value: String(record.sha.prefix(7)))
                        metadataRow(title: "Channel", value: record.releaseChannel == .beta ? "Beta" : "Stable")
                        if let committer = buildCommitterDisplay(for: record) {
                            metadataRow(title: "Committed By", value: committer)
                        } else {
                            metadataRow(title: "Committed By", value: "Resolving…")
                        }
                        if let summary = record.summary, !summary.isEmpty {
                            metadataRow(title: "Summary", value: summary)
                        }
                        if let logPath = record.logPath, !logPath.isEmpty {
                            metadataRow(title: "Log Path", value: logPath)
                        }
                    }
                    .glassSection()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actions")
                            .font(.headline)
                        if let commitURL {
                            Link(destination: commitURL) {
                                Label("Open Commit on GitHub", systemImage: "link")
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        if let logPath = record.logPath, !logPath.isEmpty {
                            Button {
                                revealLog(at: logPath)
                            } label: {
                                Label("Reveal Build Log in Finder", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .glassSection()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 620, minHeight: 420)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Label("v\(record.version)", systemImage: record.releaseChannel == .beta ? "flask.fill" : "checkmark.seal.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(record.releaseChannel == .beta ? .orange : .green)
                    if record.releaseChannel == .beta {
                        Text("Beta")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Done") {
                        closeDetails()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            appState.ensureBuildCommitAuthor(for: repository.id, sha: record.sha)
        }
    }

    private func compareURL(for release: GitHubReleaseSummary, in releases: [GitHubReleaseSummary]) -> URL? {
        guard let index = releases.firstIndex(where: { $0.id == release.id }),
              index + 1 < releases.count else {
            return nil
        }
        let older = releases[index + 1]
        return URL(string: "https://github.com/\(repository.owner)/\(repository.repo)/compare/\(older.tagName)...\(release.tagName)")
    }

    private func renderedReleaseNotesView(for rawNotes: String) -> some View {
        let notes = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if notes.isEmpty {
                Text("No release notes available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if looksLikeHTML(notes),
                      let attributed = htmlAttributedString(from: notes) {
                Text(attributed)
                    .font(.callout)
                    .textSelection(.enabled)
            } else if looksLikeMarkdown(notes),
                      let attributed = try? AttributedString(markdown: notes) {
                Text(attributed)
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Text(notes)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

    private func looksLikeHTML(_ text: String) -> Bool {
        guard text.contains("<"), text.contains(">") else {
            return false
        }
        return text.range(of: "<[^>]+>", options: .regularExpression) != nil
    }

    private func looksLikeMarkdown(_ text: String) -> Bool {
        let markdownHints = [
            "# ",
            "## ",
            "### ",
            "- ",
            "* ",
            "1. ",
            "```",
            "[",
            "](",
            "**",
            "_"
        ]
        return markdownHints.contains(where: { text.contains($0) })
    }

    private func htmlAttributedString(from html: String) -> AttributedString? {
        guard let data = html.data(using: .utf8) else {
            return nil
        }
        guard let parsed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            return nil
        }
        return try? AttributedString(parsed, including: AttributeScopes.FoundationAttributes.self)
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func revealLog(at path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expandedPath)])
    }

    @ViewBuilder
    private func buildAuthorLine(for record: BuildRecord) -> some View {
        if let authorLogin = record.authorLogin, !authorLogin.isEmpty {
            HStack(spacing: 6) {
                if let avatarURL = record.authorAvatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Circle()
                                .fill(.thinMaterial)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                }

                if let profileURL = record.authorProfileURL {
                    Link("@\(authorLogin)", destination: profileURL)
                        .font(.caption2.weight(.semibold))
                } else {
                    Text("@\(authorLogin)")
                        .font(.caption2.weight(.semibold))
                }
                Text("committed this build")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let fallbackAuthor = appState.buildCommitAuthor(for: repository.id, sha: record.sha) {
            HStack(spacing: 6) {
                if let avatarURL = appState.buildCommitAuthorAvatarURL(for: repository.id, sha: record.sha) {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Circle()
                                .fill(.thinMaterial)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let profileURL = appState.buildCommitAuthorProfileURL(for: repository.id, sha: record.sha) {
                    Link(fallbackAuthor, destination: profileURL)
                        .font(.caption2.weight(.semibold))
                } else {
                    Text(fallbackAuthor)
                        .font(.caption2.weight(.semibold))
                }
                Text("committed this build")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Resolving committer…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                appState.ensureBuildCommitAuthor(for: repository.id, sha: record.sha)
            }
        }
    }

    private func buildCommitterDisplay(for record: BuildRecord) -> String? {
        if let authorLogin = record.authorLogin, !authorLogin.isEmpty {
            return "@\(authorLogin)"
        }
        return appState.buildCommitAuthor(for: repository.id, sha: record.sha)
    }

    @ViewBuilder
    private func releaseAuthorLine(for release: GitHubReleaseSummary) -> some View {
        if let author = release.author {
            HStack(spacing: 6) {
                if let avatarURL = author.avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Circle()
                                .fill(.thinMaterial)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
                }

                if let profileURL = author.profileURL {
                    Link("@\(author.login)", destination: profileURL)
                        .font(.caption2.weight(.semibold))
                } else {
                    Text("@\(author.login)")
                        .font(.caption2.weight(.semibold))
                }
                Text("published this release")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func releaseExplorerRefreshLabel(from date: Date?) -> String {
        guard let date else {
            return "Not refreshed yet"
        }
        return "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }
}

private func repositoryStatusSymbol(for activity: RepositoryActivity) -> String {
    switch activity {
    case .idle:
        return "minus.circle.fill"
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
