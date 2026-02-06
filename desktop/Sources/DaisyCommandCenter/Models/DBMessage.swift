import Foundation
import GRDB

struct DBMessage: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "message"

    var id: String
    var taskId: String
    var role: String
    var text: String
    var timestamp: Date
    var persona: String

    init(id: String = UUID().uuidString, taskId: String, role: String, text: String, persona: String = "manager") {
        self.id = id
        self.taskId = taskId
        self.role = role
        self.text = text
        self.timestamp = Date()
        self.persona = persona
    }

    static let task = belongsTo(DBTask.self)
}
