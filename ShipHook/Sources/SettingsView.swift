import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updater: AppUpdater
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                generalPanel
                launchAtLoginPanel
                updatePanel
                filesPanel
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 460)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.cyan.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
        .onAppear {
            appState.refreshLaunchAtLoginStatus()
        }
    }

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("General", systemImage: "slider.horizontal.3")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 14) {
                settingsField(
                    title: "Poll Interval (Seconds)",
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

                settingsField(
                    title: "GitHub Token Variable",
                    symbol: "key.horizontal",
                    text: Binding(
                        get: { appState.configuration.githubTokenEnvVar ?? "" },
                        set: { appState.configuration.githubTokenEnvVar = $0.isEmpty ? nil : $0 }
                    ),
                    prompt: "GITHUB_TOKEN"
                )
            }

            Text("GitHub token is optional for public repositories, recommended for rate limits, and required for private repositories. ShipHook reads the token from the environment variable named above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassSection()
    }

    private var launchAtLoginPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Launch at Login", systemImage: "power")
                .font(.title3.bold())

            Toggle(isOn: Binding(
                get: { appState.launchesAtLogin },
                set: { newValue in
                    do {
                        try appState.setLaunchAtLogin(newValue)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = error.localizedDescription
                        appState.refreshLaunchAtLoginStatus()
                    }
                }
            )) {
                Text("Open ShipHook automatically when you log in")
            }
            .toggleStyle(.switch)

            if let message = launchAtLoginError ?? appState.launchAtLoginStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(launchAtLoginError == nil ? Color.secondary : Color.red)
            }
        }
        .glassSection()
    }

    private var updatePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Updates", systemImage: "sparkles")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 14) {
                summaryItem(title: "Feed", value: updater.feedURLString.isEmpty ? "Not configured" : updater.feedURLString, symbol: "link")
                summaryItem(title: "Public Key", value: updater.hasPublicKey ? "Installed" : "Missing", symbol: "key")
            }

            Text(updater.isConfigured ? "ShipHook is configured for Sparkle self-updates." : "ShipHook still needs a valid Sparkle feed and public key to self-update.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassSection()
    }

    private var filesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Files", systemImage: "folder")
                .font(.title3.bold())

            summaryItem(title: "Config Location", value: appState.configPath, symbol: "doc.text")

            HStack {
                Button {
                    appState.openConfigInFinder()
                } label: {
                    Label("Reveal Config", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(GlassActionButtonStyle())

                Button {
                    appState.loadConfiguration()
                } label: {
                    Label("Reload Config", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .buttonStyle(GlassActionButtonStyle())

                Spacer()
            }
        }
        .glassSection()
    }

    private func settingsField(title: String, symbol: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryItem(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
