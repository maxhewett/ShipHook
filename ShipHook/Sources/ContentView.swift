import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ShipHook")
                    .font(.largeTitle.bold())
                Spacer()
                Button("Check Now") {
                    appState.triggerManualPoll()
                }
                Button("Reveal Config") {
                    appState.openConfigInFinder()
                }
            }

            Text(appState.configPath)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let error = appState.lastGlobalError {
                Text(error)
                    .foregroundStyle(.red)
            }

            List(appState.configuration.repositories, id: \.id) { repo in
                let state = appState.repoStates[repo.id] ?? .initial(id: repo.id)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(repo.name)
                            .font(.headline)
                        Spacer()
                        Text(state.activity.rawValue.capitalized)
                            .foregroundStyle(color(for: state.activity))
                    }
                    Text("\(repo.owner)/\(repo.repo) @ \(repo.branch)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(state.summary)
                    if let error = state.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    if !state.lastLog.isEmpty {
                        Text(state.lastLog)
                            .font(.caption.monospaced())
                            .lineLimit(6)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
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
}
