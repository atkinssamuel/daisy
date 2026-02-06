import Foundation

struct Criterion: Identifiable, Codable, Equatable {
    let id: String
    let taskId: String
    let text: String
    let isValidated: Bool
    let isHumanValidated: Bool

    init(
        id: String = UUID().uuidString,
        taskId: String,
        text: String,
        isValidated: Bool = false,
        isHumanValidated: Bool = false
    ) {
        self.id = id
        self.taskId = taskId
        self.text = text
        self.isValidated = isValidated
        self.isHumanValidated = isHumanValidated
    }
}
