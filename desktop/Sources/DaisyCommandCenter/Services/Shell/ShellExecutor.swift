import Foundation

/// Unified shell command execution
struct ShellExecutor {
    /// Execute a shell command and return output
    /// - Parameters:
    ///   - command: Full command string to execute
    ///   - arguments: Array of arguments to pass to the command
    ///   - workingDirectory: Optional working directory for the command
    /// - Returns: Command output as string
    static func execute(
        _ command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil
    ) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: outputData, encoding: .utf8) ?? ""
        } catch {
            return "Error executing command: \(error)"
        }
    }

    /// Execute a shell command via /bin/bash
    /// - Parameter command: Shell command to execute
    /// - Returns: Command output as string
    static func executeShell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: outputData, encoding: .utf8) ?? ""
        } catch {
            return "Error executing shell command: \(error)"
        }
    }
}
