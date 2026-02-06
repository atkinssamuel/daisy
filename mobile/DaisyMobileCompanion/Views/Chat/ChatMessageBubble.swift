import SwiftUI

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let role: String
    let content: String

    var isUser: Bool { role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer() }

            Text(content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)

            if !isUser { Spacer() }
        }
    }
}
