import SwiftUI
import AppKit

// MARK: - Artifact Detail View

struct ArtifactDetailView: View {
    let artifact: DBArtifact
    @EnvironmentObject var store: DataStore
    @State private var showCopied = false

    var body: some View {
        VStack(spacing: 0) {

            // Header

            HStack {
                Button(action: { store.selectArtifact(nil) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                Image(systemName: iconForType(artifact.type))
                    .foregroundColor(colorForType(artifact.type))
                    .font(.system(size: 16))

                Text(artifact.label)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                if artifact.type == "code", let lang = artifact.language {
                    Text(lang)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.15))
                        .cornerRadius(4)
                }

                if artifact.type == "csv", let maxRows = artifact.maxRows {
                    Text("\(maxRows) rows")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }

                Spacer()

                // Copy button for markdown and image

                if artifact.type == "markdown" || artifact.type == "image" {
                    Button(action: { copyArtifact() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                            Text(showCopied ? "Copied" : "Copy")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(showCopied ? .green : .gray)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { store.deleteArtifact(artifact.id) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(white: 0.08))

            Divider().background(Color(white: 0.2))

            // Content based on type

            switch artifact.type {
            case "markdown":
                MarkdownArtifactView(content: artifact.file)
            case "code":
                CodeArtifactView(code: artifact.file, language: artifact.language ?? "plaintext", path: artifact.path, label: artifact.label)
            case "image":
                ImageArtifactView(path: artifact.path ?? "", caption: artifact.caption ?? artifact.file)
            case "csv":
                CSVArtifactView(content: artifact.file, path: artifact.path, maxRows: artifact.maxRows ?? 10)
            case "references":
                ReferencesArtifactView(jsonContent: artifact.file)
            default:

                // Fallback: plain text

                ScrollView {
                    Text(artifact.file)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .textSelection(.enabled)
                }
            }
        }
    }

    func copyArtifact() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch artifact.type {
        case "markdown":
            pasteboard.setString(artifact.file, forType: .string)
        case "image":
            if let path = artifact.path, let img = NSImage(contentsOfFile: path) {
                pasteboard.writeObjects([img])
            }
        default:
            break
        }

        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }

    func iconForType(_ type: String) -> String {
        switch type {
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "image": return "photo"
        case "csv": return "tablecells"
        case "markdown": return "doc.richtext"
        case "references": return "list.bullet.rectangle"
        default: return "doc"
        }
    }

    func colorForType(_ type: String) -> Color {
        switch type {
        case "code": return .green
        case "image": return .pink
        case "csv": return .orange
        case "markdown": return .purple
        case "references": return .blue
        default: return .gray
        }
    }
}
