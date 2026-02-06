import SwiftUI

// Kept for compatibility — redirects to AgentsList

struct TasksList: View {
    let projectId: String

    var body: some View {
        AgentsList(projectId: projectId)
    }
}
