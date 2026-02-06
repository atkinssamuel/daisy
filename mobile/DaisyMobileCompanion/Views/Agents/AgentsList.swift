import SwiftUI

// MARK: - Agents List

struct AgentsList: View {
    @EnvironmentObject var store: DataStore
    let projectId: String

    var agents: [Agent] {
        store.agentsForProject(projectId)
    }

    var projectName: String {
        store.projects.first { $0.id == projectId }?.name ?? "Project"
    }

    var body: some View {
        List {
            if agents.isEmpty {
                ContentUnavailableView(
                    "No Agents",
                    systemImage: "sparkles",
                    description: Text("Agents will appear when created on the desktop")
                )
            }

            ForEach(agents) { agent in
                NavigationLink(value: agent.id) {
                    AgentCard(agent: agent)
                }
            }
        }
        .navigationTitle(projectName)
        .navigationDestination(for: String.self) { agentId in
            ChatScreen(agentId: agentId, projectId: projectId)
        }
        .refreshable {
            await store.fetchAgents(projectId: projectId)
        }
        .task {
            await store.fetchAgents(projectId: projectId)
        }
    }
}

// MARK: - Agent Card

struct AgentCard: View {
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            HStack(spacing: 8) {
                Image(systemName: agent.isDefault ? "sparkles" : "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
                    .frame(width: 20)

                Text(agent.isDefault ? "Default Agent" : agent.title)
                    .font(.headline)

                Spacer()

                // Session status

                Circle()
                    .fill(agent.sessionRunning == true ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            // Focus or status

            if agent.isThinking == true {
                HStack(spacing: 6) {
                    ThinkingDots()
                    if let focus = agent.focus, !focus.isEmpty {
                        Text(focus)
                            .font(.caption)
                            .foregroundColor(.purple)
                            .lineLimit(1)
                    } else {
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
            } else if let focus = agent.focus, !focus.isEmpty {
                Text(focus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text(agent.sessionRunning == true ? "Idle" : "Stopped")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
