import Foundation

struct ProjectTask: Identifiable, Codable, Equatable {
    let id: String
    let projectId: String
    let title: String
    let description: String
    let status: String
    let isFinished: Bool
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        projectId: String,
        title: String,
        description: String = "",
        status: String = "inactive",
        isFinished: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.description = description
        self.status = status
        self.isFinished = isFinished
        self.createdAt = createdAt
    }
}
