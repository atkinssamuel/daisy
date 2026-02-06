import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: String
    let agentId: String
    let role: String
    let text: String
    let timestamp: Date
    let persona: String

    init(
        id: String = UUID().uuidString,
        agentId: String,
        role: String,
        text: String,
        timestamp: Date = Date(),
        persona: String = "agent"
    ) {
        self.id = id
        self.agentId = agentId
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.persona = persona
    }

    var isUser: Bool { role == "user" }
    var isAgent: Bool { role == "daisy" || role == "assistant" }
}
