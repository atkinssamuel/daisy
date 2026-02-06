import Foundation

struct Criterion: Identifiable, Codable, Equatable {
    let id: String
    let taskId: String
    let text: String
    let isVerified: Bool

    init(id: String = UUID().uuidString, taskId: String, text: String, isVerified: Bool = false) {
        self.id = id
        self.taskId = taskId
        self.text = text
        self.isVerified = isVerified
    }
}
