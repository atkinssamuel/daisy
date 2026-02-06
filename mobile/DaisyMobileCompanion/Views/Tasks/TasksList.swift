import SwiftUI

// MARK: - Tasks List View

struct TasksList: View {
    @EnvironmentObject var store: DataStore
    let projectId: String

    var projectTasks: [ProjectTask] {
        store.tasks.filter { $0.projectId == projectId }
    }

    var body: some View {
        List(projectTasks) { task in
            NavigationLink(value: task.id) {
                TaskListRow(task: task)
            }
        }
        .navigationTitle("Tasks")
        .navigationDestination(for: String.self) { taskId in
            TaskDetail(taskId: taskId)
        }
    }
}
