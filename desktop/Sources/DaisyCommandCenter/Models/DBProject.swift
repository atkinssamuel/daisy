import Foundation
import GRDB

struct DBProject: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "project"

    var id: String
    var name: String
    var description: String
    var sourceUrl: String
    var localPath: String
    var order: Int
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, description: String = "", sourceUrl: String = "", localPath: String = "", order: Int = 0) {
        self.id = id
        self.name = name
        self.description = description
        self.sourceUrl = sourceUrl
        self.localPath = localPath
        self.order = order
        self.createdAt = Date()
    }

    static let tasks = hasMany(DBTask.self)
}
