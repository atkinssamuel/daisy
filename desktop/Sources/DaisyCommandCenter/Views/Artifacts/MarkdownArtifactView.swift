import SwiftUI
import MarkdownUI

// MARK: - Markdown Artifact View

struct MarkdownArtifactView: View {
    let content: String

    var body: some View {
        HSplitView {

            // Left: Source

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Text("Source")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.06))

                ScrollView {
                    Text(content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(Color(white: 0.04))
            }
            .frame(minWidth: 200)

            // Right: Preview

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "eye")
                        .font(.system(size: 11))
                        .foregroundColor(.cyan)
                    Text("Preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cyan)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.06))

                ScrollView {
                    Markdown(content)
                        .markdownTheme(.basic)
                        .markdownSoftBreakMode(.lineBreak)
                        .markdownTextStyle {
                            ForegroundColor(.white.opacity(0.9))
                            BackgroundColor(.clear)
                            FontSize(14)
                        }
                        .markdownTextStyle(\.strong) {
                            ForegroundColor(.cyan)
                            FontWeight(.semibold)
                        }
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            configuration.label
                                .padding(12)
                                .background(Color(white: 0.1))
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .background(Color.black.opacity(0.3))
            }
            .frame(minWidth: 200)
        }
    }
}
