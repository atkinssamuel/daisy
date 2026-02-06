import SwiftUI

// MARK: - Task Detail View

struct TaskDetail: View {
    @EnvironmentObject var store: DataStore
    let taskId: String

    var task: ProjectTask? {
        store.tasks.first { $0.id == taskId }
    }

    var taskCriteria: [Criterion] {
        store.criteria.filter { $0.taskId == taskId }
    }

    var body: some View {
        if let task = task {
            List {

                // Description section

                if !task.description.isEmpty {
                    Section("Description") {
                        Text(task.description)
                            .font(.body)
                    }
                }

                // Criteria section

                Section("Criteria") {
                    if taskCriteria.isEmpty {
                        Text("No criteria defined")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(taskCriteria) { criterion in
                            HStack {
                                Image(systemName: criterion.isVerified ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(criterion.isVerified ? .green : .secondary)

                                Text(criterion.text)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .navigationTitle(task.title)
        } else {
            Text("Task not found")
                .foregroundColor(.secondary)
        }
    }
}
