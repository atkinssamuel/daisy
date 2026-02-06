import SwiftUI

// MARK: - Projects List View

struct ProjectsList: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        List(store.projects) { project in
            NavigationLink(value: project.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)

                    if !project.description.isEmpty {
                        Text(project.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Projects")
        .navigationDestination(for: String.self) { projectId in
            TasksList(projectId: projectId)
        }
    }
}
