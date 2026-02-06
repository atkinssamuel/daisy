import Foundation
import GRDB

struct DBCriterion: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "criterion"

    var id: String
    var taskId: String
    var text: String
    var isValidated: Bool
    var isHumanValidated: Bool
    var order: Int

    init(id: String = UUID().uuidString, taskId: String, text: String, isHumanValidated: Bool = false, order: Int = 0) {
        self.id = id
        self.taskId = taskId
        self.text = text
        self.isValidated = false
        self.isHumanValidated = isHumanValidated
        self.order = order
    }

    static let task = belongsTo(DBTask.self)
}

// Engineer criteria - independent from tasks, scoped to project's engineer session

struct DBEngineerCriterion: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "engineer_criterion"

    var id: String
    var projectId: String
    var text: String
    var isCompleted: Bool
    var isHumanValidated: Bool
    var createdAt: Date
    var completedAt: Date?
    var order: Int

    init(id: String = UUID().uuidString, projectId: String, text: String, isHumanValidated: Bool = false, order: Int = 0) {
        self.id = id
        self.projectId = projectId
        self.text = text
        self.isCompleted = false
        self.isHumanValidated = isHumanValidated
        self.createdAt = Date()
        self.completedAt = nil
        self.order = order
    }

    var isValidated: Bool { isCompleted }
}
