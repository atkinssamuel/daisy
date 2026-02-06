import Foundation
import Combine

// MARK: - App-Wide Data Store

class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var projects: [Project] = []
    @Published var tasks: [ProjectTask] = []
    @Published var criteria: [Criterion] = []

    @Published var currentProjectId: String?
    @Published var currentTaskId: String?

    private init() {}
}
