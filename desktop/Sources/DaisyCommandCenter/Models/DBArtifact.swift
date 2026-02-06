import Foundation
import GRDB

struct DBArtifact: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "artifact"

    var id: String
    var taskId: String
    var type: String
    var label: String
    var file: String
    var path: String?
    var description: String?
    var order: Int
    var maxRows: Int?
    var language: String?
    var cachedHighlight: String?
    var caption: String?

    init(id: String = UUID().uuidString, taskId: String, type: String, label: String, file: String = "", order: Int = 0) {
        self.id = id
        self.taskId = taskId
        self.type = type
        self.label = label
        self.file = file
        self.order = order
    }

    static let task = belongsTo(DBTask.self)
}
