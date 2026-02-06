import SwiftUI

// MARK: - Projects Sidebar

struct ProjectsSidebar: View {
    @EnvironmentObject var store: DataStore
    @State private var isAddingProject = false
    @State private var newProjectName = ""
    @FocusState private var isNewProjectFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // Header

            HStack {
                Text("Projects")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { isAddingProject = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(white: 0.1))

            Divider().background(Color(white: 0.2))

            // Add project input

            if isAddingProject {
                HStack {
                    TextField("Project name", text: $newProjectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isNewProjectFocused)
                        .onSubmit {
                            let name = newProjectName
                            newProjectName = ""
                            isAddingProject = false

                            if !name.isEmpty {
                                _ = store.createProject(name: name)
                            }
                        }

                    Button("✕") {
                        isAddingProject = false
                        newProjectName = ""
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color(white: 0.12))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNewProjectFocused = true
                    }
                }
            }

            // Project list

            ScrollView {
                VStack(spacing: 2) {
                    if store.projects.isEmpty {
                        VStack(spacing: 8) {
                            Text("No projects")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Text("Click + to create one")
                                .font(.system(size: 10))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                            ProjectRow(
                                project: project,
                                isSelected: store.currentProjectId == project.id,
                                index: index,
                                total: store.projects.count,
                                onMoveUp: { store.moveProjectUp(project.id) },
                                onMoveDown: { store.moveProjectDown(project.id) }
                            )
                            .onTapGesture {
                                store.selectProject(project.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()
        }
    }
}

// MARK: - Project Row

struct ProjectRow: View {
    let project: DBProject
    let isSelected: Bool
    let index: Int
    let total: Int
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    @ObservedObject var mcpServer = MCPServer.shared
    @State private var isHovering = false

    var hasWorkingAgents: Bool {
        mcpServer.typingIndicators.contains { key, value in
            key.hasPrefix("agent-\(project.id)") && value == true
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.gray)
                .frame(width: 20, alignment: .trailing)

            Text(project.name)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(1)

            if hasWorkingAgents {
                ThinkingDots(color: .blue)
                    .padding(.leading, 4)
            }

            Spacer()

            // Reorder buttons (only in layout when hovering)

            if isHovering {
                HStack(spacing: 4) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(index > 0 ? .gray : .gray.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(index < total - 1 ? .gray : .gray.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(index == total - 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
