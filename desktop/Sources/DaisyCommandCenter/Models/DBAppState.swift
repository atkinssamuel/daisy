import Foundation
import GRDB

struct DBAppState: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appState"

    var key: String
    var value: String
}
