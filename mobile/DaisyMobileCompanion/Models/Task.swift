import Foundation

// Agent model — maps to desktop DBTask/DBAgent

struct Agent: Identifiable, Codable, Equatable {
    let id: String
    let projectId: String
    let title: String
    let description: String
    let isDefault: Bool
    let isFinished: Bool
    let status: String
    let createdAt: Date

    // Live status fields (from polling)

    var isThinking: Bool?
    var focus: String?
    var sessionRunning: Bool?

    init(
        id: String = UUID().uuidString,
        projectId: String,
        title: String,
        description: String = "",
        isDefault: Bool = false,
        isFinished: Bool = false,
        status: String = "inactive",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.description = description
        self.isDefault = isDefault
        self.isFinished = isFinished
        self.status = status
        self.createdAt = createdAt
    }
}

// Keep old type alias for compatibility

typealias ProjectTask = Agent
