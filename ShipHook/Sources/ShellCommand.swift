import Foundation

struct CommandResult {
    var exitCode: Int32
    var output: String
}

enum CommandError: LocalizedError {
    case nonZeroExit(CommandResult)

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(result):
            return "Command failed with exit code \(result.exitCode).\n\(result.output)"
        }
    }
}

struct ShellCommandRunner {
    func run(
        _ command: String,
        currentDirectory: String,
        environment: [String: String]
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        var mergedEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { mergedEnvironment[$0.key] = $0.value }
        process.environment = mergedEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let result = CommandResult(exitCode: process.terminationStatus, output: output)

        if result.exitCode != 0 {
            throw CommandError.nonZeroExit(result)
        }

        return result
    }
}
