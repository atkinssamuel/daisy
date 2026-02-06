import SwiftUI

// MARK: - Agent Detail View

struct AgentDetail: View {
    @EnvironmentObject var store: DataStore
    @ObservedObject private var registry = TerminalViewModelRegistry.shared
    @ObservedObject private var sessionManager = ClaudeCodeManager.shared
    @State private var showTerminal = false

    var currentProject: DBProject? {
        store.projects.first { $0.id == store.currentProjectId }
    }

    var currentAgent: DBAgent? {
        guard let agentId = store.currentAgentId else { return nil }
        return store.agents.first { $0.id == agentId }
    }

    // Resolve the current session ID based on the selected agent

    var currentSessionId: String? {
        guard let projectId = store.currentProjectId,
              let agent = currentAgent else { return nil }

        if agent.isDefault {
            return ClaudeCodeManager.agentSessionId(projectId: projectId)
        } else {
            return ClaudeCodeManager.agentSessionId(projectId: projectId, agentId: agent.id)
        }
    }

    var currentTerminalViewModel: TerminalViewModel? {
        guard let sessionId = currentSessionId,
              let session = sessionManager.sessions[sessionId] else { return nil }
        return registry.viewModel(for: sessionId, session: session, store: store)
    }

    var body: some View {

        // Check if an artifact is selected

        if let artifactId = store.selectedArtifactId,
           let artifact = store.getArtifact(artifactId) {
            ArtifactDetailView(artifact: artifact)
                .id(artifactId)
        } else if currentAgent != nil {

            // Main layout: Chat + Terminal (optional)

            HStack(spacing: 0) {

                // Left: Chat interface

                AgentChatInterface(showTerminal: $showTerminal, terminalViewModel: currentTerminalViewModel)
                    .frame(maxWidth: .infinity)

                // Right: Terminal pane (when toggled on)

                if showTerminal, let vm = currentTerminalViewModel {
                    Divider().background(Color(white: 0.2))

                    TerminalPane(viewModel: vm)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            VStack {
                Text("Select an agent")
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
