import Foundation

struct Project: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let localPath: String
    let order: Int
    let createdAt: Date
    var agentCount: Int?
    var activeAgentCount: Int?

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        localPath: String = "",
        order: Int = 0,
        createdAt: Date = Date(),
        agentCount: Int? = nil,
        activeAgentCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.localPath = localPath
        self.order = order
        self.createdAt = createdAt
        self.agentCount = agentCount
        self.activeAgentCount = activeAgentCount
    }
}
