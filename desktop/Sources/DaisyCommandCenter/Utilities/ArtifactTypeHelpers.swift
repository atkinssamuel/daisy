import SwiftUI

/// Consolidated artifact and task helpers for icons, colors, and status
struct ArtifactTypeHelper {
    static func icon(forType type: String) -> String {
        switch type {
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "image": return "photo"
        case "csv": return "tablecells"
        case "markdown": return "doc.richtext"
        default: return "doc"
        }
    }

    static func color(forType type: String) -> Color {
        switch type {
        case "code": return .green
        case "image": return .pink
        case "csv": return .orange
        case "markdown": return .purple
        default: return .gray
        }
    }
}

struct TaskStatusHelper {
    static func color(for task: DBTask) -> Color {
        if task.isFinished { return .green }
        switch task.status {
        case "running": return .yellow
        case "paused": return .orange
        default: return .blue
        }
    }

    static func statusText(for task: DBTask) -> String {
        if task.isFinished { return "Finished" }
        return task.status.capitalized
    }
}

struct PersonaHelper {
    enum PersonaType {
        case agent

        var icon: String {
            return "sparkles"
        }

        var color: Color {
            return .purple
        }

        var title: String {
            return "Agent"
        }

        var fullTitle: String {
            return "Agent"
        }

        var stringValue: String {
            return "agent"
        }

        init?(from string: String) {
            switch string.lowercased() {
            case "agent": self = .agent
            default: return nil
            }
        }
    }
}
