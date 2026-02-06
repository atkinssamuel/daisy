import SwiftUI
import MarkdownUI

// MARK: - Chat Screen

struct ChatScreen: View {
    @EnvironmentObject var store: DataStore
    let agentId: String
    let projectId: String
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var agent: Agent? {
        store.agentsForProject(projectId).first { $0.id == agentId }
    }

    var messages: [Message] {
        store.messagesForAgent(agentId)
    }

    var isThinking: Bool {
        agent?.isThinking == true
    }

    var agentTitle: String {
        guard let agent = agent else { return "Agent" }
        return agent.isDefault ? "Default Agent" : agent.title
    }

    var body: some View {
        VStack(spacing: 0) {

            // Messages

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            ChatMessageBubble(role: msg.role, content: msg.text)
                                .id(msg.id)
                        }

                        if isThinking {
                            HStack(spacing: 8) {
                                ThinkingDots()
                                Text("Thinking...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .id("thinking")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Focus indicator

            if let focus = agent?.focus, !focus.isEmpty {
                HStack(spacing: 6) {
                    if isThinking {
                        ThinkingDots()
                    }

                    Text(focus)
                        .font(.caption)
                        .foregroundColor(.purple)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.08))
            }

            // Input

            HStack(spacing: 12) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(agentTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(agent?.sessionRunning == true ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    Text(agent?.sessionRunning == true ? "Running" : "Stopped")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            await store.fetchMessages(agentId: agentId)
        }
        .refreshable {
            await store.fetchMessages(agentId: agentId)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        Task {
            await store.sendMessage(agentId: agentId, projectId: projectId, text: text)
        }
    }
}
