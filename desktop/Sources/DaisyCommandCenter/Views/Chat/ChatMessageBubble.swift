import SwiftUI
import MarkdownUI

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let message: DBMessage
    var agentName: String = "Agent"
    var agentIcon: String = "sparkles"
    @State private var isHovering = false
    @State private var showCopied = false

    var isTool: Bool { message.role == "tool" }
    var isProposalAccepted: Bool { message.role == "proposal_accepted" }
    var isSystemMessage: Bool { message.role == "system" }

    var body: some View {
        if isProposalAccepted {
            proposalAcceptedCard
        } else if isSystemMessage {
            systemMessageView
        } else {
            regularMessageView
        }
    }

    // MARK: - Proposal Accepted Card

    var proposalAcceptedCard: some View {

        // Text format: "type|actionName|summary"

        let parts = message.text.split(separator: "|", maxSplits: 2).map(String.init)
        let proposalType = parts.count > 0 ? parts[0] : ""
        let actionName = parts.count > 1 ? parts[1] : ""
        let summary = parts.count > 2 ? parts[2] : ""

        let icon: String = {
            switch proposalType {
            case "create": return "plus.circle.fill"
            case "update": return "pencil.circle.fill"
            case "delete": return "trash.circle.fill"
            case "project_update": return "folder.circle.fill"
            case "start": return "play.circle.fill"
            case "finish": return "checkmark.circle.fill"
            default: return "checkmark.circle.fill"
            }
        }()

        let color: Color = {
            switch proposalType {
            case "create": return .green
            case "update": return .orange
            case "delete": return .red
            case "project_update": return .purple
            case "start": return .blue
            case "finish": return .green
            default: return .green
            }
        }()

        let label: String = {
            switch proposalType {
            case "create": return "Task Created"
            case "update": return "Task Updated"
            case "delete": return "Task Deleted"
            case "project_update": return "Project Updated"
            case "start": return "Task Started"
            case "finish": return "Task Finished"
            default: return "Approved"
            }
        }()

        return HStack(spacing: 0) {

            // Accent bar

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {

                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(color)

                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)

                    Spacer()

                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green.opacity(0.8))
                }

                if !actionName.isEmpty {
                    Text(actionName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }

                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(color.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - System Message

    var systemMessageView: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow.opacity(0.7))

            Text(message.text)
                .font(.system(size: 12))
                .foregroundColor(.yellow.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Regular Message

    var regularMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Icon + Name row

            HStack(spacing: 8) {
                if isTool {
                    Image(systemName: "terminal")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .frame(width: 18)
                    Text("Output")
                        .font(.system(size: 14))
                        .foregroundColor(.green.opacity(0.8))
                } else if message.role == "daisy" {
                    Image(systemName: agentIcon)
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                        .frame(width: 18)
                    Text(agentName)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .frame(width: 18)
                    Text("You")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }

                Spacer()

                // Copy button

                if isHovering {
                    Button(action: copyMessage) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(showCopied ? .green : .gray)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            // Markdown rendering with dark theme and colored keys

            Markdown(message.text)
                .markdownTheme(.basic)
                .markdownSoftBreakMode(.lineBreak)
                .markdownTextStyle {
                    ForegroundColor(isTool ? .green.opacity(0.9) : .white.opacity(0.9))
                    BackgroundColor(.clear)
                    FontSize(isTool ? 12 : 14)
                }
                .markdownTextStyle(\.strong) {
                    ForegroundColor(isTool ? .green : .cyan)
                    FontWeight(.semibold)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(12)
                        .background(Color(white: 0.1))
                        .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isTool ? 4 : 8)
        .background(isTool ? Color.green.opacity(0.05) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        showCopied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}
