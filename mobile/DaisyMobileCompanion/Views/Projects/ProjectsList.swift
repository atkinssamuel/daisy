import SwiftUI

// MARK: - Projects List

struct ProjectsList: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        List {
            if store.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Create a project on the desktop app")
                )
            }

            ForEach(store.projects) { project in
                NavigationLink(value: project.id) {
                    ProjectCard(project: project)
                }
            }
        }
        .navigationTitle("Projects")
        .navigationDestination(for: String.self) { projectId in
            AgentsList(projectId: projectId)
        }
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
