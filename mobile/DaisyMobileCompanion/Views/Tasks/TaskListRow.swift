import SwiftUI

// MARK: - Task List Row

struct TaskListRow: View {
    let task: ProjectTask

    var statusColor: Color {
        switch task.status {
        case "active":
            return .green
        case "inactive":
            return .gray
        default:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)

                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
