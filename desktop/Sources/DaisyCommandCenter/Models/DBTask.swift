import Foundation
import GRDB

struct DBTask: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "task"

    var id: String
    var projectId: String
    var title: String
    var description: String
    var isProjectManager: Bool
    var isFinished: Bool
    var status: String
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    // Agent alias: isDefault = isProjectManager (the default agent)

    var isDefault: Bool { isProjectManager }

    init(id: String = UUID().uuidString, projectId: String, title: String, description: String = "", isProjectManager: Bool = false) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.description = description
        self.isProjectManager = isProjectManager
        self.isFinished = false
        self.status = "inactive"
        self.createdAt = Date()
    }

    static let project = belongsTo(DBProject.self)
    static let criteria = hasMany(DBCriterion.self)
    static let messages = hasMany(DBMessage.self)
    static let logs = hasMany(DBTaskLog.self)
    static let artifacts = hasMany(DBArtifact.self)
}

// Type alias: Agents are stored in the task table

typealias DBAgent = DBTask
