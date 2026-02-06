import SwiftUI

// MARK: - Agents List

struct AgentsList: View {
    @EnvironmentObject var store: DataStore
    @ObservedObject var mcpServer = MCPServer.shared
    @State private var showBroadcastModal = false
    @State private var showClearAllContextWarning = false
    @State private var showClearAllHistoryWarning = false

    var nonDefaultAgents: [DBAgent] {
        store.agents.filter { !$0.isDefault }
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header

            HStack {
                Text("Agents")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { store.addAgent() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(white: 0.1))

            Divider().background(Color(white: 0.2))

            // Agents list

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {

                    // Default agent (always first)

                    if let defaultAgent = store.agents.first(where: { $0.isDefault }) {
                        VStack(spacing: 0) {
                            AgentListRow(
                                agent: defaultAgent,
                                isSelected: store.currentAgentId == defaultAgent.id && store.selectedArtifactId == nil,
                                index: 1,
                                total: store.agents.count,
                                canReorder: false
                            )
                            .onTapGesture {
                                store.selectAgent(defaultAgent.id)
                                store.selectArtifact(nil)
                            }

                            // Artifacts under default agent

                            if let artifacts = store.agentArtifacts[defaultAgent.id], !artifacts.isEmpty {
                                ForEach(Array(artifacts.enumerated()), id: \.element.id) { idx, artifact in
                                    ArtifactListRow(
                                        artifact: artifact,
                                        isSelected: store.selectedArtifactId == artifact.id,
                                        index: idx + 1,
                                        total: artifacts.count,
                                        canReorder: artifacts.count > 1,
                                        onMoveUp: { store.moveArtifactUp(artifact.id, agentId: defaultAgent.id) },
                                        onMoveDown: { store.moveArtifactDown(artifact.id, agentId: defaultAgent.id) }
                                    )
                                    .onTapGesture {
                                        store.selectAgent(defaultAgent.id)
                                        store.selectArtifact(artifact.id)
                                    }
                                }
                            }

                            if store.agents.count > 1 {
                                Divider()
                                    .background(Color(white: 0.2))
                                    .padding(.vertical, 8)
                            }
                        }
                    }

                    // Non-default agents

                    ForEach(Array(nonDefaultAgents.enumerated()), id: \.element.id) { index, agent in
                        VStack(spacing: 0) {
                            AgentListRow(
                                agent: agent,
                                isSelected: store.currentAgentId == agent.id && store.selectedArtifactId == nil,
                                index: index + 2,
                                total: store.agents.count,
                                canReorder: true,
                                onMoveUp: { store.moveAgentUp(agent.id) },
                                onMoveDown: { store.moveAgentDown(agent.id) }
                            )
                            .onTapGesture {
                                store.selectAgent(agent.id)
                                store.selectArtifact(nil)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    store.deleteAgent(agent.id)
                                }
                            }

                            // Artifacts under this agent

                            if let artifacts = store.agentArtifacts[agent.id], !artifacts.isEmpty {
                                ForEach(Array(artifacts.enumerated()), id: \.element.id) { idx, artifact in
                                    ArtifactListRow(
                                        artifact: artifact,
                                        isSelected: store.selectedArtifactId == artifact.id,
                                        index: idx + 1,
                                        total: artifacts.count,
                                        canReorder: artifacts.count > 1,
                                        onMoveUp: { store.moveArtifactUp(artifact.id, agentId: agent.id) },
                                        onMoveDown: { store.moveArtifactDown(artifact.id, agentId: agent.id) }
                                    )
                                    .onTapGesture {
                                        store.selectAgent(agent.id)
                                        store.selectArtifact(artifact.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider().background(Color(white: 0.2))

            // Project Actions section

            VStack(spacing: 0) {
                HStack {
                    Text("Project Actions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Broadcast

                Button(action: { showBroadcastModal = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12))
                            .foregroundStyle(LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: 16)
                        Text("Broadcast")
                            .font(.system(size: 12))
                            .foregroundStyle(LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                // Clear All Message History

                if !showClearAllHistoryWarning {
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { showClearAllHistoryWarning = true } }) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                                .frame(width: 16)
                            Text("Clear All Message History")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text("Clear all message history?")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Text("This will delete chat history for all agents. Context will be preserved.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .lineSpacing(2)

                        HStack(spacing: 8) {
                            Button(action: { withAnimation(.easeOut(duration: 0.15)) { showClearAllHistoryWarning = false } }) {
                                Text("Cancel")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(white: 0.15))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                store.clearAllMessageHistory()
                                withAnimation(.easeOut(duration: 0.15)) { showClearAllHistoryWarning = false }
                            }) {
                                Text("Clear History")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                }

                // Clear All Context

                if !showClearAllContextWarning {
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { showClearAllContextWarning = true } }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .frame(width: 16)
                            Text("Clear All Context")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                            Text("Clear all agent context?")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Text("This will restart all agent sessions, clearing their memory. Message history will be preserved.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .lineSpacing(2)

                        HStack(spacing: 8) {
                            Button(action: { withAnimation(.easeOut(duration: 0.15)) { showClearAllContextWarning = false } }) {
                                Text("Cancel")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(white: 0.15))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                store.clearAllContext()
                                withAnimation(.easeOut(duration: 0.15)) { showClearAllContextWarning = false }
                            }) {
                                Text("Clear Context")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                }

                Divider()
                    .background(Color(white: 0.2))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)

                // Project Settings

                Button(action: { store.showProjectSettings = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .frame(width: 16)
                        Text("Project Settings")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)
        }
        .sheet(isPresented: $showBroadcastModal) {
            BroadcastModal(isPresented: $showBroadcastModal)
                .environmentObject(store)
        }
    }
}
