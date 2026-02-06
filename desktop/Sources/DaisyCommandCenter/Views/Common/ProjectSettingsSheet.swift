import SwiftUI

// MARK: - Project Settings Sheet

struct ProjectSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DataStore
    @State private var projectName: String = ""
    @State private var sourceUrl: String = ""
    @State private var localPath: String = ""
    @State private var hasChanges: Bool = false
    @State private var isSaving: Bool = false
    @State private var showDeleteWarning: Bool = false

    var currentProject: DBProject? {
        store.projects.first { $0.id == store.currentProjectId }
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header

            HStack {
                Text("Project Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(white: 0.1))

            Divider().background(Color(white: 0.2))

            // Content

            VStack(alignment: .leading, spacing: 20) {

                // Project Name

                VStack(alignment: .leading, spacing: 6) {
                    Text("Project Name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)

                    TextField("Project name", text: $projectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(Color(white: 0.12))
                        .cornerRadius(8)
                        .onChange(of: projectName) { _, _ in hasChanges = true }
                }

                // Local Project Path

                VStack(alignment: .leading, spacing: 6) {
                    Text("Local Project Path")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)

                    TextField("~/projects/my-project", text: $localPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(Color(white: 0.12))
                        .cornerRadius(8)
                        .onChange(of: localPath) { _, _ in hasChanges = true }
                }

                // GitHub URL

                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub URL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)

                    TextField("https://github.com/user/repo", text: $sourceUrl)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(Color(white: 0.12))
                        .cornerRadius(8)
                        .onChange(of: sourceUrl) { _, _ in hasChanges = true }
                }
            }
            .padding(20)

            // Delete Project

            if !showDeleteWarning {
                VStack(spacing: 0) {
                    Divider().background(Color(white: 0.2))

                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { showDeleteWarning = true } }) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("Delete Project")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 0) {
                    Divider().background(Color(white: 0.2))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                            Text("Delete \"\(currentProject?.name ?? "project")\"?")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Text("This will permanently delete this project, all its tasks, messages, criteria, and artifacts. This action cannot be undone.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .lineSpacing(2)

                        HStack(spacing: 10) {
                            Button(action: { withAnimation(.easeOut(duration: 0.15)) { showDeleteWarning = false } }) {
                                Text("Cancel")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color(white: 0.15))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button(action: deleteProject) {
                                Text("Delete Project")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.red)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.06))
                }
            }

            Divider().background(Color(white: 0.2))

            // Footer with Save button

            HStack {
                Spacer()

                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Button(action: saveSettings) {
                    Text(isSaving ? "Saving..." : "Save Changes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 100)
                        .padding(.vertical, 10)
                        .background(hasChanges ? Color.blue : Color.gray.opacity(0.4))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!hasChanges || projectName.isEmpty || isSaving)
            }
            .padding(16)
            .background(Color(white: 0.08))
        }
        .frame(width: 550)
        .onAppear {
            if let project = currentProject {
                projectName = project.name
                sourceUrl = project.sourceUrl
                localPath = project.localPath
            }
        }
    }

    func saveSettings() {
        guard let projectId = store.currentProjectId else { return }
        isSaving = true

        store.updateProjectSettings(projectId, name: projectName, description: "", sourceUrl: sourceUrl, localPath: localPath)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isSaving = false
            hasChanges = false
            dismiss()
        }
    }

    func deleteProject() {
        guard let projectId = store.currentProjectId else { return }
        dismiss()
        store.deleteProject(projectId)
    }
}
