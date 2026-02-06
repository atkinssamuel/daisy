import Foundation
import GRDB

struct DBTaskLog: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "taskLog"

    var id: String
    var taskId: String
    var type: String
    var message: String
    var details: String?
    var timestamp: Date

    init(id: String = UUID().uuidString, taskId: String, type: String, message: String, details: String? = nil) {
        self.id = id
        self.taskId = taskId
        self.type = type
        self.message = message
        self.details = details
        self.timestamp = Date()
    }

    static let task = belongsTo(DBTask.self)
}
