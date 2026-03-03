import SwiftUI
import AppKit

@main
struct ShipHookApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra("ShipHook", systemImage: "shippingbox") {
            MenuBarContentView()
                .environmentObject(appState)
                .environmentObject(updater)
        }

        Window("ShipHook", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
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

            Button("Check for Updates...") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)

            Button("Reveal Config") {
                appState.openConfigInFinder()
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
    }
}
