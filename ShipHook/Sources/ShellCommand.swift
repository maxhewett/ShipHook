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
            return "Command failed with exit code \(result.exitCode).\n\(Self.outputSummary(result.output))"
        }
    }

    private static func outputSummary(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No command output was captured."
        }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let interestingLines = lines.filter { line in
            let lowercased = line.lowercased()
            return lowercased.contains("error:")
                || lowercased.contains("fatal:")
                || lowercased.contains("failed")
                || lowercased.contains("permission denied")
                || lowercased.contains("could not")
        }
        let selectedLines = (interestingLines.isEmpty ? Array(lines.suffix(12)) : Array(interestingLines.suffix(10)))
        let summary = selectedLines
            .map { line -> String in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count > 360 {
                    return "\(text.prefix(360))..."
                }
                return text
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if !summary.isEmpty {
            return summary
        }
        if trimmed.count > 360 {
            return "\(trimmed.prefix(360))..."
        }
        return trimmed
    }
}

struct ShellCommandRunner {
    func run(
        _ command: String,
        currentDirectory: String,
        environment: [String: String]
    ) throws -> CommandResult {
        try run(
            command,
            currentDirectory: currentDirectory,
            environment: environment,
            onOutput: nil
        )
    }

    func run(
        _ command: String,
        currentDirectory: String,
        environment: [String: String],
        onOutput: ((String) -> Void)?
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

        var outputData = Data()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                return
            }

            outputData.append(data)
            if let chunk = String(data: data, encoding: .utf8) {
                onOutput?(chunk)
            }
        }

        try process.run()
        process.waitUntilExit()
        handle.readabilityHandler = nil

        let remainingData = handle.readDataToEndOfFile()
        if !remainingData.isEmpty {
            outputData.append(remainingData)
            if let chunk = String(data: remainingData, encoding: .utf8) {
                onOutput?(chunk)
            }
        }

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let result = CommandResult(exitCode: process.terminationStatus, output: output)

        if result.exitCode != 0 {
            throw CommandError.nonZeroExit(result)
        }

        return result
    }
}
