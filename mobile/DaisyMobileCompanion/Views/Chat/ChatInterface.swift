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
        .task {
            store.listenToMessages(agentId: agentId)
        }
        .onDisappear {
            store.stopListeningToMessages(agentId: agentId)
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
