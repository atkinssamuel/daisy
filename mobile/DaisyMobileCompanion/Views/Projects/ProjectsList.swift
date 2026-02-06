import SwiftUI

// MARK: - Projects List

struct ProjectsList: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        List {
            if store.projects.isEmpty && store.isConnected {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Create a project on the desktop app")
                )
            } else if !store.isConnected {
                ContentUnavailableView(
                    "Not Connected",
                    systemImage: "wifi.slash",
                    description: Text("Check server address in Settings")
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
        .refreshable {
            await store.fetchProjects()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ConnectionDot(isConnected: store.isConnected)
            }
        }
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: Project
    @EnvironmentObject var store: DataStore

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

            HStack(spacing: 12) {
                if let count = project.agentCount {
                    Label("\(count) agent\(count == 1 ? "" : "s")", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let active = project.activeAgentCount, active > 0 {
                    HStack(spacing: 4) {
                        ThinkingDots()
                        Text("\(active) thinking")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Connection Dot

struct ConnectionDot: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Connected" : "Offline")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Thinking Dots

struct ThinkingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.purple)
                    .frame(width: 5, height: 5)
                    .opacity(dotOpacity(index: i))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                phase = 1.0
            }
        }
    }

    func dotOpacity(index: Int) -> Double {
        let offset = Double(index) * 0.3
        return 0.3 + 0.7 * max(0, sin(.pi * (phase + offset)))
    }
}
