import Foundation

// MARK: - Pending Proposal

struct PendingProposal: Identifiable {
    let id = UUID()
    let type: ProposalType
    let params: [String: Any]
    let summary: String
    let taskId: String
    let projectId: String

    enum ProposalType {
        case create
        case update
        case delete
        case projectUpdate
        case start
        case finish
    }
}
