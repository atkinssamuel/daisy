import SwiftUI

// MARK: - Agent List Row

struct AgentListRow: View {
    let agent: DBAgent
    let isSelected: Bool
    var index: Int = 1
    var total: Int = 1
    var canReorder: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    @EnvironmentObject var store: DataStore
    @ObservedObject var mcpServer = MCPServer.shared
    @State private var isHovering = false

    var nonDefaultAgents: [DBAgent] {
        store.agents.filter { !$0.isDefault }
    }

    var agentIndex: Int {
        if agent.isDefault { return 0 }
        return nonDefaultAgents.firstIndex(where: { $0.id == agent.id }) ?? 0
    }

    var agentSessionId: String {
        if agent.isDefault {
            return ClaudeCodeManager.agentSessionId(projectId: agent.projectId)
        } else {
            return ClaudeCodeManager.agentSessionId(projectId: agent.projectId, agentId: agent.id)
        }
    }

    var isThinking: Bool {
        mcpServer.typingIndicators[agentSessionId] ?? false
    }

    var focusText: String? {
        mcpServer.focusStrings[agentSessionId]
    }

    var body: some View {
        HStack(spacing: 8) {

            // Index number

            Text("\(index).")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.gray)
                .frame(width: 20, alignment: .trailing)

            // Agent icon (pulsing if thinking)

            Image(systemName: agent.isDefault ? "sparkles" : iconForAgent(agent.title))
                .font(.system(size: 12))
                .foregroundColor(agent.isDefault ? .purple : .cyan)
                .frame(width: 20, height: 20)
                .opacity(isThinking ? 0.5 : 1.0)
                .animation(isThinking ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: isThinking)

            // Name and focus

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.isDefault ? "Default Agent" : agent.title)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(focusText ?? "No focus")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            if isThinking {
                ThinkingDots()
                    .padding(.leading, 4)
            }

            Spacer()

            // Artifact count badge

            let artifactCount = store.agentArtifacts[agent.id]?.count ?? 0
            if artifactCount > 0 {
                Text("\(artifactCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(white: 0.15))
                    .cornerRadius(8)
            }

            // Up/down buttons and delete on hover (only in layout when hovering)

            if canReorder && isHovering {
                HStack(spacing: 4) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(agentIndex > 0 ? .gray : .gray.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(agentIndex == 0)

                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(agentIndex < nonDefaultAgents.count - 1 ? .gray : .gray.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(agentIndex == nonDefaultAgents.count - 1)

                    Button(action: { store.deleteAgent(agent.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.purple.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Artifact List Row (nested under agent)

struct ArtifactListRow: View {
    let artifact: DBArtifact
    let isSelected: Bool
    var index: Int = 1
    var total: Int = 1
    var canReorder: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    @EnvironmentObject var store: DataStore
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {

            // Indent + number

            Color.clear.frame(width: 8)

            Text("\(index).")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundColor(.gray)
                .frame(width: 18, alignment: .trailing)

            Image(systemName: iconForType(artifact.type))
                .font(.system(size: 10))
                .foregroundColor(.purple)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)

                if let caption = artifact.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Reorder and delete buttons on hover (only in layout when hovering)

            if isHovering {
                if canReorder {
                    HStack(spacing: 4) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(index > 1 ? .gray : .gray.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(index <= 1)

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(index < total ? .gray : .gray.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                        .disabled(index >= total)

                        Button(action: { store.deleteArtifact(artifact.id) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                    }
                } else {
                    Button(action: { store.deleteArtifact(artifact.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.purple.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    func iconForType(_ type: String) -> String {
        switch type {
        case "code": return "doc.text"
        case "image": return "photo"
        case "csv": return "tablecells"
        case "markdown": return "doc.richtext"
        case "references": return "list.bullet.rectangle"
        case "file": return "doc"
        case "note": return "note.text"
        default: return "doc"
        }
    }
}

// MARK: - Thinking Dots Animation

struct ThinkingDots: View {
    var color: Color = .purple
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(animationPhase == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}
