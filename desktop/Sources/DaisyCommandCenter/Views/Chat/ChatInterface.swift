import SwiftUI
import MarkdownUI

// MARK: - Agent Chat Interface (unified agent)
// All communication flows: User input -> tmux session -> Claude Code -> MCP tools -> UI

// Type alias for backward compatibility
typealias ManagerChatInterface = AgentChatInterface

struct AgentChatInterface: View {
    @EnvironmentObject var store: DataStore
    @ObservedObject var mcpServer = MCPServer.shared
    @Binding var showTerminal: Bool
    var terminalViewModel: TerminalViewModel?
    @State private var inputText = ""

    // Current agent

    var currentAgent: DBAgent? {
        guard let agentId = store.currentAgentId else { return nil }
        return store.agents.first { $0.id == agentId }
    }

    // Get the current session for the agent

    var currentSession: ClaudeCodeSession? {
        guard let projectId = store.currentProjectId,
              let agent = currentAgent else { return nil }

        let sessionId: String
        if agent.isDefault {
            sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)
        } else {
            sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agent.id)
        }
        return ClaudeCodeManager.shared.sessions[sessionId]
    }

    // Check if Claude is typing (MCP-based: true on user send, false on Claude reply)

    var isTyping: Bool {
        guard let session = currentSession else { return false }
        return mcpServer.typingIndicators[session.id] ?? false
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header - Agent

            HStack(spacing: 12) {

                // Agent icon in circle

                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 36, height: 36)
                    if let agent = currentAgent {
                        Image(systemName: agent.isDefault ? "sparkles" : iconForAgent(agent.title))
                            .font(.system(size: 16))
                            .foregroundColor(.purple)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let agent = currentAgent {
                        Text(agent.isDefault ? "Default Agent" : agent.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("Agent")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }

                    if let project = store.projects.first(where: { $0.id == store.currentProjectId }) {
                        Text(project.name)
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Session status indicator

                if let session = currentSession {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(session.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(session.isRunning ? "Running" : "Stopped")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .padding(.trailing, 8)
                }

                // Terminal toggle

                HStack(spacing: 4) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 10))
                        .foregroundColor(showTerminal ? .orange : .gray)

                    Toggle("", isOn: $showTerminal)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.65)
                }
                .padding(.trailing, 4)

                Button(action: copyChat) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                        Text("Copy")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                Button(action: { store.clearMessageHistory() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Clear History")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)

                Button(action: { store.clearContext() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                        Text("Clear Context")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(white: 0.08))

            Divider().background(Color(white: 0.2))

            // Messages - using ScrollView + LazyVStack for instant switching

            // Flipped ScrollView - content naturally appears at bottom without scrolling

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {

                        Color.clear.frame(height: 20).id("top")

                        if isTyping {
                            HStack(spacing: 8) {
                                if let agent = currentAgent {
                                    Image(systemName: agent.isDefault ? "sparkles" : iconForAgent(agent.title))
                                        .font(.system(size: 14))
                                        .foregroundColor(.purple)
                                        .frame(width: 18)
                                }
                                Text("Thinking")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                ThinkingDots()
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .scaleEffect(x: 1, y: -1)
                            .id("typing")
                        }

                        ForEach(store.messages.reversed()) { msg in
                            ChatMessageBubble(
                                message: msg,
                                agentName: currentAgent?.isDefault == true ? "Default Agent" : (currentAgent?.title ?? "Agent"),
                                agentIcon: currentAgent?.isDefault == true ? "sparkles" : iconForAgent(currentAgent?.title ?? "")
                            )
                            .scaleEffect(x: 1, y: -1)
                            .id(msg.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scaleEffect(x: 1, y: -1)
                .id(store.currentAgentId)
                .onChange(of: store.messages.count) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
                .onChange(of: isTyping) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }

            Divider().background(Color(white: 0.2))

            // Input area

            VStack(spacing: 0) {
                Divider().background(Color(white: 0.2))

                HStack(alignment: .bottom, spacing: 12) {
                    ZStack(alignment: .leading) {

                        // Placeholder

                        if inputText.isEmpty {
                            Text("Message...")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding(.leading, 12)
                        }

                        // Expanding text input

                        ExpandingMessageInput(
                            text: $inputText,
                            placeholder: "",
                            onSubmit: handleInput,
                            onEscape: handleEscape
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .background(Color(white: 0.1))
                    .cornerRadius(8)

                    Button(action: handleInput) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(inputText.isEmpty ? .gray : .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            }
            .background(Color(white: 0.06))
        }
    }

    func copyChat() {
        let chatText = store.messages.map { msg -> String in
            let role = msg.role == "daisy" ? "Agent" : "You"
            return "[\(role)]\n\(msg.text)"
        }.joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(chatText, forType: .string)
    }

    func handleEscape() {
        ensureSessionExists()

        if let session = currentSession, session.isRunning {
            session.sendInterrupt()

            // Clear typing/thinking indicators

            MCPServer.shared.typingIndicators[session.id] = false
            terminalViewModel?.clearThinking()

            store.addMessage(role: "system", text: "⎋ User pressed Escape — interrupted", persona: "agent", toAgentId: store.currentAgentId)
        }
    }

    func handleInput() {
        logDebug("handleInput called, inputText: '\(inputText)'")
        sendMessage()
    }

    func sendMessageToSession(_ text: String) {

        // Add to local message history

        store.addMessage(role: "user", text: text, persona: "agent", toAgentId: store.currentAgentId)

        // Get or create session for this agent

        ensureSessionExists()

        // Send to tmux session

        if let session = currentSession {
            session.sendLine(text)
        }

        terminalViewModel?.userDidSend()
    }

    func sendMessage() {
        logDebug("sendMessage called with inputText: '\(inputText)'")
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            logDebug("sendMessage: text is empty, returning")
            return
        }

        logDebug("sendMessage: sending '\(text)'")
        inputText = ""

        // Add to local message history

        store.addMessage(role: "user", text: text, persona: "agent", toAgentId: nil)

        // Get or create session

        ensureSessionExists()

        // Send to tmux session

        if let session = currentSession {
            logDebug("Sending to session \(session.id): '\(text)'")
            session.sendLine(text)
        } else {
            logDebug("ERROR: currentSession is nil after ensureSessionExists!")
        }

        terminalViewModel?.userDidSend()
    }

    func logDebug(_ msg: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".daisy-debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(msg)\n"
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

    func ensureSessionExists() {
        guard let projectId = store.currentProjectId,
              let agent = currentAgent else {
            logDebug("ensureSessionExists: No project or agent selected")
            return
        }

        logDebug("ensureSessionExists: projectId=\(projectId), agentId=\(agent.id)")

        let manager = ClaudeCodeManager.shared
        let project = store.projects.first { $0.id == projectId }
        let workingDir = project?.localPath.isEmpty == false ? project?.localPath : nil

        let sessionId: String
        if agent.isDefault {
            sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId)
        } else {
            sessionId = ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agent.id)
        }

        if manager.sessions[sessionId] == nil {
            let session = manager.getOrCreateSession(
                id: sessionId,
                workingDirectory: workingDir,
                persona: .agent,
                projectId: projectId,
                taskId: agent.isDefault ? nil : agent.id,
                taskTitle: agent.isDefault ? nil : agent.title
            )
            session.start()
        } else if manager.sessions[sessionId]?.isRunning == false {
            manager.sessions[sessionId]?.start()
        }
    }
}

// MARK: - Broadcast Modal

struct BroadcastModal: View {
    @EnvironmentObject var store: DataStore
    @Binding var isPresented: Bool
    @State private var selectedAgentIds: Set<String> = []
    @State private var messageText = ""
    @State private var isHoveringAgent: String? = nil
    @State private var didInitialize = false

    var body: some View {
        VStack(spacing: 0) {

            // Header

            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))

                Text("Broadcast")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(white: 0.08))

            Divider().background(Color(white: 0.2))

            // Agent selection

            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Text("Select Agents")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: selectAll) {
                        Text(selectedAgentIds.count == store.agents.count ? "Deselect All" : "Select All")
                            .font(.system(size: 12))
                            .foregroundColor(.purple)
                    }
                    .buttonStyle(.plain)
                }

                // Agent grid

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(store.agents) { agent in
                        BroadcastAgentCard(
                            agent: agent,
                            isSelected: selectedAgentIds.contains(agent.id),
                            isHovering: isHoveringAgent == agent.id,
                            onTap: { toggleAgent(agent.id) }
                        )
                        .onHover { hovering in
                            isHoveringAgent = hovering ? agent.id : nil
                        }
                    }
                }
            }
            .padding(20)

            Divider().background(Color(white: 0.2))

            // Message input

            // Message input

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("\(selectedAgentIds.count) agent\(selectedAgentIds.count == 1 ? "" : "s") selected")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                HStack(alignment: .bottom, spacing: 12) {
                    ZStack(alignment: .leading) {
                        if messageText.isEmpty {
                            Text("Broadcast message...")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding(.leading, 12)
                        }

                        ExpandingMessageInput(
                            text: $messageText,
                            placeholder: "",
                            onSubmit: sendBroadcast,
                            onEscape: { isPresented = false }
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .background(Color(white: 0.1))
                    .cornerRadius(8)

                    Button(action: sendBroadcast) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                canSend ?
                                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [.gray], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(Color(white: 0.06))
        }
        .frame(width: 500)
        .background(Color(white: 0.12))
        .onAppear {
            if !didInitialize {
                selectedAgentIds = Set(store.agents.map { $0.id })
                didInitialize = true
            }
        }
    }

    var canSend: Bool {
        !selectedAgentIds.isEmpty && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func selectAll() {
        if selectedAgentIds.count == store.agents.count {
            selectedAgentIds.removeAll()
        } else {
            selectedAgentIds = Set(store.agents.map { $0.id })
        }
    }

    func toggleAgent(_ id: String) {
        if selectedAgentIds.contains(id) {
            selectedAgentIds.remove(id)
        } else {
            selectedAgentIds.insert(id)
        }
    }

    func sendBroadcast() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !selectedAgentIds.isEmpty else { return }

        store.broadcastMessage(text, toAgentIds: Array(selectedAgentIds))
        isPresented = false
    }
}

// MARK: - Broadcast Agent Card

struct BroadcastAgentCard: View {
    let agent: DBAgent
    let isSelected: Bool
    let isHovering: Bool
    let onTap: () -> Void
    @ObservedObject var mcpServer = MCPServer.shared

    var focusText: String? {
        let sessionId: String
        if agent.isDefault {
            sessionId = "agent-\(agent.projectId)"
        } else {
            sessionId = "agent-\(agent.projectId)_\(agent.id)"
        }
        return mcpServer.focusStrings[sessionId]
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {

                // Icon with glow effect when selected

                ZStack {
                    Circle()
                        .fill(
                            isSelected ?
                                RadialGradient(
                                    colors: [.purple.opacity(0.4), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 22
                                ) :
                                RadialGradient(
                                    colors: [.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 22
                                )
                        )

                    Circle()
                        .fill(isSelected ? Color.purple : Color(white: 0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ?
                                        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                        LinearGradient(colors: [Color(white: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 2
                                )
                        )

                    Image(systemName: agent.isDefault ? "sparkles" : iconForAgent(agent.title))
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? .white : .gray)
                }
                .frame(width: 44, height: 44)

                // Name

                Text(agent.isDefault ? "Default" : agent.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .gray)
                    .lineLimit(1)

                Text(focusText ?? "No focus")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovering ? Color(white: 0.15) : Color(white: 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

