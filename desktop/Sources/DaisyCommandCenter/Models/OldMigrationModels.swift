import Foundation

// -------------------------------------------------------------------------------------
// -------------------------------- JSON Migration -------------------------------------
// -------------------------------------------------------------------------------------

struct OldProjectsManifest: Codable {
    var projects: [OldProject]
}

struct OldProject: Codable {
    var id: String
    var name: String
    var order: Int
}

struct OldTasksManifest: Codable {
    var tasks: [OldTask]
}

struct OldTask: Codable {
    var id: String
    var title: String
    var description: String
    var successCriteria: [OldCriterion]
    var humanValidatedCriteria: [OldCriterion]
}

struct OldCriterion: Codable {
    var id: String
    var text: String
    var isValidated: Bool
}

struct OldMessage: Codable {
    var id: UUID
    var role: OldRole
    var text: String
    var timestamp: Date

    enum OldRole: String, Codable {
        case user, daisy
    }
}
