import SwiftUI
import AppKit

// MARK: - Reference Model

struct ReferenceItem: Identifiable {
    let id = UUID()
    let url: String
    let caption: String
}

// MARK: - Reference Card Metadata

struct ReferenceMetadata {
    var title: String?
    var faviconData: Data?
}

// MARK: - References Artifact View

struct ReferencesArtifactView: View {
    let jsonContent: String
    @State private var references: [ReferenceItem] = []
    @State private var metadata: [String: ReferenceMetadata] = [:]

    var body: some View {
        ScrollView {
            if references.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text("No references found")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(references) { ref in
                        ReferenceCardView(
                            reference: ref,
                            metadata: metadata[ref.url]
                        )
                    }
                }
                .padding(20)
            }
        }
        .background(Color(white: 0.05))
        .task {
            parseReferences()
            await fetchAllMetadata()
        }
    }

    private func parseReferences() {
        guard let data = jsonContent.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        references = array.compactMap { dict in
            guard let url = dict["url"] as? String else { return nil }
            let caption = dict["caption"] as? String ?? ""
            return ReferenceItem(url: url, caption: caption)
        }
    }

    private func fetchAllMetadata() async {
        await withTaskGroup(of: (String, ReferenceMetadata?).self) { group in
            for ref in references {
                group.addTask {
                    let meta = await fetchMetadata(for: ref.url)
                    return (ref.url, meta)
                }
            }

            for await (url, meta) in group {
                if let meta = meta {
                    await MainActor.run {
                        metadata[url] = meta
                    }
                }
            }
        }
    }

    private func fetchMetadata(for urlString: String) async -> ReferenceMetadata? {
        guard let url = URL(string: urlString) else { return nil }

        var meta = ReferenceMetadata()

        // Fetch page HTML for title

        if let (data, response) = try? await URLSession.shared.data(from: url),
           let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200,
           let html = String(data: data, encoding: .utf8) {

            meta.title = extractMeta(html, property: "og:title")
                ?? extractTag(html, tag: "title")
        }

        // Fetch favicon

        if let host = url.host,
           let scheme = url.scheme,
           let faviconUrl = URL(string: "\(scheme)://\(host)/favicon.ico"),
           let (favData, favResp) = try? await URLSession.shared.data(from: faviconUrl),
           let favHttp = favResp as? HTTPURLResponse,
           favHttp.statusCode == 200 {
            meta.faviconData = favData
        }

        return meta
    }
}

// MARK: - Reference Card View

struct ReferenceCardView: View {
    let reference: ReferenceItem
    let metadata: ReferenceMetadata?
    @State private var isHovering = false

    var domain: String {
        URL(string: reference.url)?.host ?? reference.url
    }

    var body: some View {
        HStack(spacing: 12) {

            // Favicon

            if let favData = metadata?.faviconData, let nsImage = NSImage(data: favData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 4) {

                // Title or domain

                Text(metadata?.title ?? domain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Caption

                if !reference.caption.isEmpty {
                    Text(reference.caption)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }

                // URL

                Text(reference.url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.blue.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(white: 0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? Color.blue.opacity(0.5) : Color(white: 0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            if let url = URL(string: reference.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - HTML Parsing Helpers

func extractMeta(_ html: String, property: String) -> String? {
    let pattern = "<meta[^>]*property=[\"']\(property)[\"'][^>]*content=[\"']([^\"']*)[\"']"
    let altPattern = "<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*property=[\"']\(property)[\"']"

    if let match = html.range(of: pattern, options: .regularExpression) {
        let sub = html[match]
        if let contentRange = sub.range(of: "content=[\"']", options: .regularExpression),
           let endQuote = sub[contentRange.upperBound...].firstIndex(where: { $0 == "\"" || $0 == "'" }) {
            return String(sub[contentRange.upperBound..<endQuote])
        }
    }

    if let match = html.range(of: altPattern, options: .regularExpression) {
        let sub = html[match]
        if let contentRange = sub.range(of: "content=[\"']", options: .regularExpression),
           let endQuote = sub[contentRange.upperBound...].firstIndex(where: { $0 == "\"" || $0 == "'" }) {
            return String(sub[contentRange.upperBound..<endQuote])
        }
    }

    return nil
}

func extractMeta(_ html: String, name: String) -> String? {
    let pattern = "<meta[^>]*name=[\"']\(name)[\"'][^>]*content=[\"']([^\"']*)[\"']"
    let altPattern = "<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*name=[\"']\(name)[\"']"

    for pat in [pattern, altPattern] {
        if let match = html.range(of: pat, options: .regularExpression) {
            let sub = html[match]
            if let contentRange = sub.range(of: "content=[\"']", options: .regularExpression),
               let endQuote = sub[contentRange.upperBound...].firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                return String(sub[contentRange.upperBound..<endQuote])
            }
        }
    }

    return nil
}

func extractTag(_ html: String, tag: String) -> String? {
    let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
    if let match = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
        let sub = String(html[match])
        if let start = sub.range(of: ">"),
           let end = sub.range(of: "</", options: .backwards) {
            let content = sub[start.upperBound..<end.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        }
    }
    return nil
}
