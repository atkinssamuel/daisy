import SwiftUI

// MARK: - CSV Artifact View

struct CSVArtifactView: View {
    let content: String
    let path: String?
    let maxRows: Int

    var parsedData: [[String]] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.prefix(maxRows + 1).map { line in

            // Simple CSV parsing (doesn't handle quoted commas)

            line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    var headers: [String] {
        parsedData.first ?? []
    }

    var rows: [[String]] {
        Array(parsedData.dropFirst())
    }

    var body: some View {
        VStack(spacing: 0) {

            // Info bar

            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                    .font(.system(size: 11))
                Text("Showing \(rows.count) of \(maxRows) preview rows")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                if let path = path {
                    Text("• \(path)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))

            // Table

            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {

                    // Header row

                    HStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                            Text(header)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan)
                                .frame(minWidth: 100, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(white: 0.1))
                            if idx < headers.count - 1 {
                                Divider().background(Color(white: 0.2))
                            }
                        }
                    }

                    Divider().background(Color(white: 0.3))

                    // Data rows

                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                                Text(cell)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(minWidth: 100, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(rowIdx % 2 == 0 ? Color.clear : Color(white: 0.08))
                                if colIdx < row.count - 1 {
                                    Divider().background(Color(white: 0.15))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
