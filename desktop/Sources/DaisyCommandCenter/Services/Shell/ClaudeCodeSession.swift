import Foundation
import AppKit

// MARK: - Claude Code Process Manager (tmux-based)
// Each persona = own tmux session + own Claude Code instance
// All communication via MCP tools (send_message, etc.)

class ClaudeCodeManager: ObservableObject {
    static let shared = ClaudeCodeManager()

    // Active Claude Code sessions: sessionId -> ClaudeCodeSession
    @Published var sessions: [String: ClaudeCodeSession] = [:]

    private init() {
        restoreExistingSessions()
    }

    // MARK: - Session Management

    func getOrCreateSession(id: String, workingDirectory: String? = nil, persona: Persona, projectId: String, taskId: String? = nil, taskTitle: String? = nil) -> ClaudeCodeSession {
        if let existing = sessions[id] {

            // Update taskId and taskTitle in case they weren't set on restore

            if taskId != nil { existing.taskId = taskId }
            if taskTitle != nil { existing.taskTitle = taskTitle }
            return existing
        }

        let session = ClaudeCodeSession(
            id: id,
            workingDirectory: workingDirectory ?? FileManager.default.currentDirectoryPath,
            persona: persona,
            projectId: projectId,
            taskId: taskId,
            taskTitle: taskTitle
        )
        sessions[id] = session

        return session
    }

    func removeSession(id: String) {
        sessions[id]?.terminate()
        sessions.removeValue(forKey: id)
    }

    func sessionExists(id: String) -> Bool {
        sessions[id] != nil
    }

    // MARK: - Restore Sessions

    private func restoreExistingSessions() {
        let result = shell("tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^daisy-'")
        let sessionNames = result.split(separator: "\n").map { String($0) }

        for name in sessionNames {

            // Session name format: daisy-{sessionId}
            // Session ID format: agent-{projectId}

            let sessionId = String(name.dropFirst("daisy-".count))

            // Parse session ID to determine persona and project ID

            var projectId = ""

            if sessionId.hasPrefix("agent-") {
                let remainder = String(sessionId.dropFirst("agent-".count))

                // Check if non-default agent (contains underscore)

                if remainder.contains("_") {
                    let parts = remainder.split(separator: "_", maxSplits: 1)
                    projectId = String(parts[0])
                } else {
                    projectId = remainder
                }
            } else {

                // Unknown format (legacy pm-/eng-/exec-), skip

                print("⚠ Unknown session format: \(sessionId)")
                continue
            }

            // Create session object (will reconnect to existing tmux)

            let session = ClaudeCodeSession(
                id: sessionId,
                workingDirectory: FileManager.default.currentDirectoryPath,
                persona: .agent,
                projectId: projectId,
                taskId: nil,
                taskTitle: nil
            )
            session.reconnect()
            sessions[sessionId] = session
        }

        if !sessionNames.isEmpty {
            print("✓ Restored \(sessionNames.count) existing sessions")
        }
    }

    private func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        try? process.run()

        // Read output BEFORE waitUntilExit to avoid pipe buffer deadlock

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Persona Type

enum Persona: String {
    case agent = "agent"
}

// MARK: - Individual Claude Code Session (tmux-based)
// Claude communicates with UI via MCP tools (send_message, etc.)

class ClaudeCodeSession: ObservableObject, Identifiable {
    let id: String
    let workingDirectory: String
    let persona: Persona
    let projectId: String
    var taskId: String?
    var taskTitle: String?

    @Published var isRunning: Bool = false
    @Published var status: SessionStatus = .stopped

    enum SessionStatus: Equatable {
        case stopped
        case starting
        case running
        case crashed
        case restarting
    }

    var onStatusChange: ((SessionStatus) -> Void)?

    var tmuxSessionName: String { "daisy-\(id)" }

    init(id: String, workingDirectory: String, persona: Persona, projectId: String, taskId: String?, taskTitle: String?) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.persona = persona
        self.projectId = projectId
        self.taskId = taskId
        self.taskTitle = taskTitle
    }

    // MARK: - Process Control

    private func logDebug(_ msg: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".daisy-debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [Session] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let handle = try? FileHandle(forWritingTo: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
    }

    func start() {
        guard !isRunning else {
            logDebug("Session \(id) already running")
            return
        }

        logDebug("Starting session: \(id) in \(workingDirectory)")
        status = .starting
        onStatusChange?(.starting)

        // Check if tmux session already exists
        if tmuxSessionExists() {
            logDebug("Session \(tmuxSessionName) already exists, reconnecting")
            reconnect()
            return
        }

        // Build minimal system prompt for this persona
        let systemPrompt = buildSystemPrompt()

        // Write system prompt to a temp file to avoid shell escaping issues
        let promptFile = FileManager.default.temporaryDirectory.appendingPathComponent("daisy-prompt-\(id).md")
        let scriptFile = FileManager.default.temporaryDirectory.appendingPathComponent("daisy-start-\(id).sh")

        do {
            try systemPrompt.write(to: promptFile, atomically: true, encoding: .utf8)
            logDebug("Wrote system prompt to: \(promptFile.path)")

            // Write a startup script that reads the prompt file
            // Expand ~ to $HOME for shell compatibility
            let expandedDir = workingDirectory.replacingOccurrences(of: "~", with: "$HOME")
            let script = """
            #!/bin/bash
            cd "\(expandedDir)" 2>/dev/null || cd "$HOME"
            claude --dangerously-skip-permissions --system-prompt "$(cat '\(promptFile.path)')"
            """
            try script.write(to: scriptFile, atomically: true, encoding: .utf8)

            // Make script executable
            shell("chmod +x '\(scriptFile.path)'")
        } catch {
            logDebug("Failed to write files: \(error)")
        }

        // Create tmux session running the script
        let cmd = "tmux new-session -d -s '\(tmuxSessionName)' '\(scriptFile.path)'"
        logDebug("Running: \(cmd)")
        let result = shell(cmd)
        if !result.isEmpty {
            logDebug("tmux output: \(result)")
        }

        // Wait a moment for tmux to start
        Thread.sleep(forTimeInterval: 0.5)

        // Verify the session started

        if tmuxSessionExists() {
            logDebug("Session \(tmuxSessionName) started successfully")

            // Set isRunning immediately so sendLine works right away

            self.isRunning = true

            DispatchQueue.main.async {
                self.status = .running
                self.onStatusChange?(.running)
            }

            // Initialize message queue for this session

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                MCPServer.shared.sessionMessages[self.id] = []
            }
        } else {
            logDebug("FAILED to start tmux session \(tmuxSessionName)")
            self.isRunning = false
            DispatchQueue.main.async {
                self.status = .stopped
                self.onStatusChange?(.stopped)
            }
        }
    }

    // MARK: - System Prompts (minimal, per persona)

    private func buildSystemPrompt() -> String {
        let agentName = taskTitle ?? "Default Agent"
        let isDefault = taskTitle == nil

        return """
        You are \(agentName)\(isDefault ? "" : " — embrace this persona and its pop culture origins").
        You work in the codebase and help the user accomplish their goals.

        RULES:
        1. Communicate ONLY via `daisy send_message`. Never print/echo.
        2. KEEP MESSAGES BRIEF — 1-3 sentences max. Use artifacts for detailed content.
        3. Use Bash, Read, Write, etc. for engineering work.
        4. Create artifacts to share code, data, images, and documentation with the user.
        5. NEVER use interactive commands (vim, less, y/n prompts, pagers). Headless session.
        6. Run `daisy list_artifacts` before creating artifacts (upserts by label+type).
        7. ALWAYS use CSV artifacts (`--type "csv"`) instead of creating .csv files. Present data as artifacts, not files.
        8. For explanations, analysis, or documentation longer than 3 sentences — create a markdown artifact.
        9. ALWAYS use `--done false` on every send_message UNTIL you have fully completed all work for the user's request.
        10. Only use `--done true` (or omit --done) on your FINAL message after ALL work is finished. This clears the thinking indicator — do NOT clear it prematurely.
        11. ALWAYS include --focus with send_message (7 words or less describing current activity).
        12. Update focus when starting new work. When done, set focus to a summary of what you did.

        CRITICAL — FILE CLAIMS (parallel agent safety):
        You are one of multiple agents working on this project in parallel.
        Use `daisy list_claims` to see what files OTHER agents are currently editing.

        Before using Edit or Write on ANY file, you MUST:
        1. Call `daisy list_claims` to see what other agents are working on
        2. Call `daisy check_claims` to see if your target file is available
        3. Call `daisy claim_files` to acquire exclusive access
        4. Only then edit the file
        5. Call `daisy release_files` when done editing

        If a file is blocked by another agent, check_claims shows seconds until expiry.
        Wait for expiry, then retry. Claims auto-expire after 2 minutes.
        NEVER skip this process — editing without claiming causes conflicts with parallel agents.

        CLI format: `daisy <tool> --key "value" --key2 "value2"`

        Tools:
        - Communication: send_message (--done true clears thinking indicator)
        - Discovery: get_project, get_artifact_types
        - Artifacts: add_artifact, list_artifacts, delete_artifact
        - File Claims: check_claims, claim_files, release_files, list_claims

        Session ID: \(id)  |  Project ID: \(projectId)

        Examples:
        ```
        daisy send_message --session_id "\(id)" --message "Looking into it..." --done false --focus "Reviewing auth module"
        daisy send_message --session_id "\(id)" --message "Done!" --focus "Fixed auth token refresh"
        daisy check_claims --session_id "\(id)" --files '["src/foo.swift"]'
        daisy claim_files --session_id "\(id)" --files '["src/foo.swift"]'
        daisy release_files --session_id "\(id)" --files '["src/foo.swift"]'
        daisy add_artifact --session_id "\(id)" --type "code" --label "Source" --path "/path/to/file.py" --language "python" --caption "Main code"
        ```
        """
    }

    func reconnect() {
        if tmuxSessionExists() {

            // Set isRunning synchronously to avoid race condition
            // (same pattern as start() — UI may read this immediately)

            self.isRunning = true

            DispatchQueue.main.async {
                self.status = .running
                self.onStatusChange?(.running)
            }
        } else {
            self.isRunning = false

            DispatchQueue.main.async {
                self.status = .stopped
                self.onStatusChange?(.stopped)
            }
        }
    }

    private func tmuxSessionExists() -> Bool {
        let result = shell("tmux has-session -t '\(tmuxSessionName)' 2>&1")
        if result.contains("no server") || result.contains("no session") || result.contains("can't find") {
            return false
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Terminal Capture

    func capturePane(lines: Int = 500) -> String {
        let result = shell("tmux capture-pane -t '\(tmuxSessionName)' -p -e -S -\(lines)")
        return result
    }

    // MARK: - Input

    func send(_ text: String) {
        guard isRunning else { return }

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
            .replacingOccurrences(of: "\"", with: "\\\"")

        shell("tmux send-keys -t '\(tmuxSessionName)' '\(escaped)'")
    }

    // Send a command without triggering typing indicator

    func sendCommand(_ text: String) {
        guard isRunning else { return }

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")

        shell("tmux send-keys -t '\(tmuxSessionName)' -l '\(escaped)'")
        shell("tmux send-keys -t '\(tmuxSessionName)' Enter")
    }

    func sendLine(_ text: String) {
        logDebug("sendLine called with text: '\(text)', isRunning: \(isRunning)")

        guard isRunning else {
            logDebug("sendLine: NOT running, returning early")
            return
        }

        // Record user message in MCP

        MCPServer.shared.addUserMessage(sessionId: id, content: text)

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")

        // Send text with -l flag for literal interpretation, then Enter separately

        let textCmd = "tmux send-keys -t '\(tmuxSessionName)' -l '\(escaped)'"
        logDebug("sendLine executing text: \(textCmd)")
        let textResult = shell(textCmd)
        logDebug("sendLine text result: '\(textResult)'")

        let enterCmd = "tmux send-keys -t '\(tmuxSessionName)' Enter"
        logDebug("sendLine executing enter: \(enterCmd)")
        let enterResult = shell(enterCmd)
        logDebug("sendLine enter result: '\(enterResult)'")
    }

    func sendInterrupt() {
        guard isRunning else { return }
        shell("tmux send-keys -t '\(tmuxSessionName)' Escape")
    }

    func sendCtrlC() {
        guard isRunning else { return }
        shell("tmux send-keys -t '\(tmuxSessionName)' C-c")
    }

    func sendKey(_ key: String) {
        guard isRunning else { return }

        switch key.lowercased() {
        case "escape", "esc":
            shell("tmux send-keys -t '\(tmuxSessionName)' Escape")
        case "enter", "return":
            shell("tmux send-keys -t '\(tmuxSessionName)' Enter")
        case "tab":
            shell("tmux send-keys -t '\(tmuxSessionName)' Tab")
        case "backspace":
            shell("tmux send-keys -t '\(tmuxSessionName)' BSpace")
        case "ctrl+c":
            shell("tmux send-keys -t '\(tmuxSessionName)' C-c")
        case "ctrl+d":
            shell("tmux send-keys -t '\(tmuxSessionName)' C-d")
        default:
            send(key)
        }
    }

    // MARK: - Lifecycle

    func terminate() {

        // Kill the tmux session

        shell("tmux kill-session -t '\(tmuxSessionName)' 2>/dev/null")

        // Verify it's gone, retry if needed

        for _ in 0..<3 {
            if !tmuxSessionExists() { break }
            Thread.sleep(forTimeInterval: 0.1)
            shell("tmux kill-session -t '\(tmuxSessionName)' 2>/dev/null")
        }

        DispatchQueue.main.async {
            self.isRunning = false
            self.status = .stopped
            self.onStatusChange?(.stopped)
        }
    }

    func forceRestart() {

        // Kill existing tmux session if it exists

        if tmuxSessionExists() {
            shell("tmux kill-session -t '\(tmuxSessionName)' 2>/dev/null")
            Thread.sleep(forTimeInterval: 0.2)
        }

        isRunning = false
        status = .stopped

        // Start fresh

        start()
    }

    @discardableResult
    private func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        try? process.run()

        // Read output BEFORE waitUntilExit to avoid pipe buffer deadlock
        // (large output fills pipe buffer, blocking process, deadlocking waitUntilExit)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Session ID Helpers

extension ClaudeCodeManager {

    // Generate session ID for a project's default agent
    static func agentSessionId(projectId: String) -> String {
        "agent-\(projectId)"
    }

    // Generate session ID for a specific agent (non-default agents include agentId)
    // Uses underscore delimiter to distinguish from UUID hyphens
    static func agentSessionId(projectId: String, agentId: String) -> String {
        "agent-\(projectId)_\(agentId)"
    }

}
