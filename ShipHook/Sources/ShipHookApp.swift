import SwiftUI
import AppKit

@main
struct ShipHookApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
                .environmentObject(updater)
        } label: {
            MenuBarStatusIcon()
        }

        Window("ShipHook", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}

private struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updater: AppUpdater
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ShipHook")
                .font(.headline)

            ForEach(appState.configuration.repositories, id: \.id) { repo in
                let state = appState.repoStates[repo.id] ?? .initial(id: repo.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                    Text(state.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button("Check Now") {
                appState.triggerManualPoll()
            }

            Button("Open Dashboard") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Settings...") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Check for Updates...") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
    }
}

private struct MenuBarStatusIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let image = MenuBarIconProvider.statusItemImage(for: colorScheme)
        Image(nsImage: image)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .frame(width: 16, height: 16)
            .help("ShipHook")
            .accessibilityLabel("ShipHook")
    }
}

private enum MenuBarIconProvider {
    private static let darkName = "shiphoookglyphwhite"
    private static let lightName = "shiphoookglyphblack"

    static func statusItemImage(for colorScheme: ColorScheme) -> NSImage {
        let name = colorScheme == .dark ? darkName : lightName
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            image.size = NSSize(width: 16, height: 16)
            return image
        }

        if #available(macOS 12.0, *) {
            let image = NSWorkspace.shared.icon(for: .application)
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            return image
        }

        let image = NSWorkspace.shared.icon(forFileType: "app")
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
