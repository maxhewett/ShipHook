import Foundation

struct BuildHistoryStore {
    private let fileManager = FileManager.default

    private var appSupportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ShipHook", isDirectory: true)
    }

    private var historyURL: URL {
        appSupportDirectory.appendingPathComponent("build-history.json")
    }

    func loadHistory() throws -> [BuildRecord] {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            return []
        }

        let data = try Data(contentsOf: historyURL)
        return try JSONDecoder().decode([BuildRecord].self, from: data)
    }

    func saveHistory(_ history: [BuildRecord]) throws {
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        try data.write(to: historyURL, options: .atomic)
    }
}
