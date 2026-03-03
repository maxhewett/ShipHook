import SwiftUI
import AppKit

@main
struct ShipHookApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("ShipHook", systemImage: "shippingbox") {
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
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }

                Button("Reveal Config") {
                    appState.openConfigInFinder()
                }

                Divider()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(12)
            .environmentObject(appState)
        }

        Window("ShipHook", id: "main") {
            ContentView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
