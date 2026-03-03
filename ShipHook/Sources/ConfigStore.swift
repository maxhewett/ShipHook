import Foundation

enum ConfigStoreError: LocalizedError {
    case bundledSampleMissing

    var errorDescription: String? {
        switch self {
        case .bundledSampleMissing:
            return "The bundled sample configuration could not be found."
        }
    }
}

struct ConfigStore {
    let fileManager = FileManager.default

    var appSupportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ShipHook", isDirectory: true)
    }

    var configURL: URL {
        appSupportDirectory.appendingPathComponent("config.json")
    }

    mutating func loadConfiguration() throws -> AppConfiguration {
        try ensureConfigExists()
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    mutating func ensureConfigExists() throws {
        if fileManager.fileExists(atPath: configURL.path) {
            return
        }

        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)

        guard let bundledURL = Bundle.main.url(forResource: "SampleConfig", withExtension: "json") else {
            throw ConfigStoreError.bundledSampleMissing
        }

        try fileManager.copyItem(at: bundledURL, to: configURL)
    }
}
