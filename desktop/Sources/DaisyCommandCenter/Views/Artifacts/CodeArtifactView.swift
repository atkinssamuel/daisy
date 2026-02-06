import SwiftUI
import AppKit
import Highlightr

// MARK: - File Node Model

class FileNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]

    init(name: String, path: String, isDirectory: Bool, children: [FileNode] = []) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
    }
}

// MARK: - Code Artifact View (VSCode-like: file tree sidebar + code viewer)

struct CodeArtifactView: View {
    let code: String
    let language: String
    let path: String?
    let label: String

    @State private var highlightedLines: [HighlightedLine] = []
    @State private var fileTree: [FileNode] = []
    @State private var selectedFilePath: String? = nil
    @State private var currentCode: String = ""
    @State private var currentLanguage: String = "plaintext"
    @State private var isLargeFile: Bool = false
    @State private var hasChanges: Bool = false
    @State private var refreshTimer: Timer? = nil

    init(code: String, language: String, path: String? = nil, label: String = "code") {
        self.code = code
        self.language = language
        self.path = path
        self.label = label
    }

    var body: some View {
        HSplitView {

            // Left: File tree sidebar

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("FILES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.gray)

                    Spacer()

                    if hasChanges {
                        Button(action: {
                            buildFileTree()
                            hasChanges = false
                        }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 5, height: 5)
                                Text("Refresh")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider().background(Color(white: 0.2))

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(fileTree) { node in
                            FileTreeRow(node: node, selectedPath: $selectedFilePath, onSelect: selectFile)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 250)
            .background(Color(white: 0.07))

            // Right: Code viewer

            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        if isLargeFile {
                            Text("File too large for syntax highlighting")
                                .font(.system(size: 11))
                                .foregroundColor(.orange.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(white: 0.1))
                        }

                        if !highlightedLines.isEmpty {
                            ForEach(highlightedLines) { line in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(line.lineNumber)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.gray.opacity(0.5))
                                        .frame(width: line.gutterWidth, alignment: .trailing)

                                    Text(" \u{2502} ")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.gray.opacity(0.3))

                                    Text(line.attributedContent)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
            }
            .background(Color(white: 0.05))
        }
        .onAppear {
            buildFileTree()
            startChangeDetection()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .task(id: currentCode) {
            await highlightCode()
        }
    }

    // MARK: - Change Detection

    private func startChangeDetection() {
        guard let path = path else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async {
                let changed = Self.detectChanges(dirPath: path, currentTree: fileTree, selectedFile: selectedFilePath, currentCode: currentCode)
                if changed {
                    DispatchQueue.main.async { hasChanges = true }
                }
            }
        }
    }

    private static func detectChanges(dirPath: String, currentTree: [FileNode], selectedFile: String?, currentCode: String) -> Bool {
        let fm = FileManager.default

        // Check if selected file content changed

        if let filePath = selectedFile, !filePath.isEmpty,
           let data = fm.contents(atPath: filePath),
           let newCode = String(data: data, encoding: .utf8),
           newCode != currentCode {
            return true
        }

        // Check if file count changed (lightweight proxy for tree changes)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { return false }

        let currentCount = countFiles(in: currentTree)
        let diskCount = countFilesOnDisk(path: dirPath)
        return currentCount != diskCount
    }

    private static func countFiles(in nodes: [FileNode]) -> Int {
        nodes.reduce(0) { $0 + (($1.isDirectory) ? countFiles(in: $1.children) : 1) }
    }

    private static func countFilesOnDisk(path: String) -> Int {
        let fm = FileManager.default
        let skipDirs: Set<String> = [
            ".git", "node_modules", ".build", ".swiftpm", "__pycache__",
            ".DS_Store", ".env", "venv", ".venv", "dist", "build",
            ".next", ".nuxt", "coverage", ".cache", "Pods"
        ]

        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return 0 }
        var count = 0

        for item in contents {
            if item.hasPrefix(".") && item != ".gitignore" { continue }
            if skipDirs.contains(item) { continue }

            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            if isDir.boolValue {
                count += countFilesOnDisk(path: fullPath)
            } else {
                count += 1
            }
        }
        return count
    }

    // MARK: - File Tree Building

    private func buildFileTree() {
        if let path = path {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                if isDir.boolValue {

                    // Directory mode

                    let rootNode = scanDirectory(path: path)
                    fileTree = rootNode.children
                    if let firstFile = findFirstFile(in: fileTree) {
                        selectFile(firstFile.path)
                    }
                    return
                } else {

                    // Single file mode

                    let name = (path as NSString).lastPathComponent
                    let node = FileNode(name: name, path: path, isDirectory: false)
                    fileTree = [node]
                    selectFile(path)
                    return
                }
            }
        }

        // Inline code mode

        let node = FileNode(name: label, path: "", isDirectory: false)
        fileTree = [node]
        selectedFilePath = ""
        currentCode = code
        currentLanguage = language
    }

    private func scanDirectory(path: String) -> FileNode {
        let fm = FileManager.default
        let name = (path as NSString).lastPathComponent
        let node = FileNode(name: name, path: path, isDirectory: true)

        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return node
        }

        let skipDirs: Set<String> = [
            ".git", "node_modules", ".build", ".swiftpm", "__pycache__",
            ".DS_Store", ".env", "venv", ".venv", "dist", "build",
            ".next", ".nuxt", "coverage", ".cache", "Pods"
        ]

        var dirs: [FileNode] = []
        var files: [FileNode] = []

        for item in contents {
            if item.hasPrefix(".") && item != ".gitignore" { continue }
            if skipDirs.contains(item) { continue }

            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            if isDir.boolValue {
                let child = scanDirectory(path: fullPath)
                dirs.append(child)
            } else {
                files.append(FileNode(name: item, path: fullPath, isDirectory: false))
            }
        }

        // Sort: directories first (alphabetical), then files (alphabetical)

        dirs.sort { $0.name.lowercased() < $1.name.lowercased() }
        files.sort { $0.name.lowercased() < $1.name.lowercased() }
        node.children = dirs + files

        return node
    }

    private func findFirstFile(in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if !node.isDirectory { return node }
            if let found = findFirstFile(in: node.children) { return found }
        }
        return nil
    }

    // MARK: - File Selection

    private func selectFile(_ filePath: String) {
        selectedFilePath = filePath

        if filePath.isEmpty {

            // Inline code

            currentCode = code
            currentLanguage = language
            isLargeFile = false
            return
        }

        guard let data = FileManager.default.contents(atPath: filePath) else {
            currentCode = "// Error: Could not read file"
            currentLanguage = "plaintext"
            isLargeFile = false
            return
        }

        isLargeFile = data.count > 100_000
        currentCode = String(data: data, encoding: .utf8) ?? "// Binary file"
        currentLanguage = detectLanguage(for: filePath)
    }

    // MARK: - Language Detection

    private func detectLanguage(for filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        let map: [String: String] = [
            "py": "python", "swift": "swift", "js": "javascript",
            "ts": "typescript", "tsx": "typescript", "jsx": "javascript",
            "rs": "rust", "go": "go", "rb": "ruby", "java": "java",
            "c": "c", "h": "c", "cpp": "cpp", "hpp": "cpp",
            "css": "css", "html": "html", "htm": "html",
            "json": "json", "md": "markdown", "yaml": "yaml",
            "yml": "yaml", "sh": "bash", "bash": "bash",
            "sql": "sql", "xml": "xml", "toml": "toml",
            "kt": "kotlin", "dart": "dart", "php": "php",
            "r": "r", "m": "objectivec", "mm": "objectivec",
            "zig": "zig", "lua": "lua", "pl": "perl",
            "ex": "elixir", "exs": "elixir", "erl": "erlang",
            "hs": "haskell", "scala": "scala", "cs": "csharp",
            "fs": "fsharp", "vue": "html", "svelte": "html"
        ]
        return map[ext] ?? "plaintext"
    }

    // MARK: - Syntax Highlighting

    private func highlightCode() async {
        let src = currentCode
        let lang = isLargeFile ? "" : currentLanguage

        let result: [HighlightedLine] = await Task.detached(priority: .userInitiated) {
            let highlighter = Highlightr()
            highlighter?.setTheme(to: "atom-one-dark")

            let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let lines = src.components(separatedBy: "\n")
            let gutterDigits = "\(lines.count)".count
            let gutterWidth = CGFloat(gutterDigits) * 7.2 + 4

            // Skip highlighting for large files or unknown language

            guard !lang.isEmpty,
                  let highlighted = highlighter?.highlight(src, as: lang) else {
                return lines.enumerated().map { idx, line in
                    let num = String(idx + 1)
                    let pad = String(repeating: " ", count: gutterDigits - num.count)
                    return HighlightedLine(
                        id: idx,
                        lineNumber: "\(pad)\(num)",
                        attributedContent: AttributedString(line),
                        gutterWidth: gutterWidth
                    )
                }
            }

            let nsString = highlighted.string as NSString
            var searchStart = 0
            var result: [HighlightedLine] = []

            for lineIdx in 0..<lines.count {
                let num = String(lineIdx + 1)
                let pad = String(repeating: " ", count: gutterDigits - num.count)

                let lineNSLength = (lines[lineIdx] as NSString).length
                var attrContent = AttributedString("")

                if lineNSLength > 0 && searchStart + lineNSLength <= nsString.length {
                    let lineRange = NSRange(location: searchStart, length: lineNSLength)
                    let lineAttr = highlighted.attributedSubstring(from: lineRange)
                    let mutable = NSMutableAttributedString(attributedString: lineAttr)
                    mutable.addAttribute(.font, value: monoFont, range: NSRange(location: 0, length: mutable.length))

                    if let converted = try? AttributedString(mutable, including: \.appKit) {
                        attrContent = converted
                    } else {
                        attrContent = AttributedString(lines[lineIdx])
                    }
                }

                searchStart += lineNSLength
                if lineIdx < lines.count - 1 {
                    searchStart += 1
                }

                result.append(HighlightedLine(
                    id: lineIdx,
                    lineNumber: "\(pad)\(num)",
                    attributedContent: attrContent,
                    gutterWidth: gutterWidth
                ))
            }

            return result
        }.value

        await MainActor.run {
            highlightedLines = result
        }
    }
}

// MARK: - File Tree Row

struct FileTreeRow: View {
    @ObservedObject var node: FileNode
    @Binding var selectedPath: String?
    let onSelect: (String) -> Void
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if node.isDirectory {

                // Directory row

                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                            .frame(width: 12)

                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue.opacity(0.7))

                        Text(node.name)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(node.children) { child in
                        FileTreeRow(node: child, selectedPath: $selectedPath, onSelect: onSelect)
                            .padding(.leading, 12)
                    }
                }
            } else {

                // File row

                Button(action: { onSelect(node.path) }) {
                    HStack(spacing: 4) {
                        Color.clear.frame(width: 12)

                        Image(systemName: fileIcon(for: node.name))
                            .font(.system(size: 11))
                            .foregroundColor(fileColor(for: node.name))

                        Text(node.name)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(selectedPath == node.path ? Color.blue.opacity(0.3) : Color.clear)
                    .cornerRadius(3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "rb", "java", "c", "cpp", "h", "cs":
            return "doc.text"
        case "json", "yaml", "yml", "toml", "xml":
            return "doc.badge.gearshape"
        case "md", "txt", "rst":
            return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "svg", "ico":
            return "photo"
        case "css", "scss", "less":
            return "paintbrush"
        case "html", "htm":
            return "globe"
        case "sh", "bash", "zsh":
            return "terminal"
        default:
            return "doc"
        }
    }

    private func fileColor(for name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .green
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "go": return .cyan
        case "rs": return .orange
        case "rb": return .red
        case "java": return .orange
        case "json": return .yellow
        case "md": return .purple
        case "html", "htm": return .orange
        case "css", "scss": return .blue
        default: return .gray
        }
    }
}

// MARK: - Highlighted Line Model

struct HighlightedLine: Identifiable {
    let id: Int
    let lineNumber: String
    let attributedContent: AttributedString
    let gutterWidth: CGFloat
}
