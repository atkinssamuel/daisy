import SwiftUI
import MarkdownUI

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let role: String
    let content: String

    var isUser: Bool { role == "user" }
    var isSystem: Bool { role == "system" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            if isSystem {

                // System messages centered and dim

                Text(content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

            } else if isUser {

                // User messages: blue, right-aligned

                Text(content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)

            } else {

                // Agent messages: rendered as markdown

                Markdown(content)
                    .markdownTextStyle(\.text) {
                        FontSize(15)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(16)
            }

            if !isUser && !isSystem { Spacer(minLength: 60) }
        }
    }
}
