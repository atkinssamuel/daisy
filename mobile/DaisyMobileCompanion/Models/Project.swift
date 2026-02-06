import Foundation

struct Project: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let createdAt: Date

    init(id: String = UUID().uuidString, name: String, description: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
    }
}
