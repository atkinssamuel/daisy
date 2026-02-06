import Foundation
import GRDB

struct DBFileClaim: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "file_claim"

    var id: String
    var projectId: String
    var agentId: String
    var filePath: String
    var claimedAt: Date

    init(id: String = UUID().uuidString, projectId: String, agentId: String, filePath: String) {
        self.id = id
        self.projectId = projectId
        self.agentId = agentId
        self.filePath = filePath
        self.claimedAt = Date()
    }

    static let project = belongsTo(DBProject.self)
    static let agent = belongsTo(DBTask.self, using: ForeignKey(["agentId"]))
}
