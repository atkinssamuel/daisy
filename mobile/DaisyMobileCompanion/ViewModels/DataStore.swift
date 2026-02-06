import Foundation
import Combine
import FirebaseFirestore

// MARK: - App-Wide Data Store (Firestore-backed)

@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()

    // MARK: - Data

    @Published var projects: [Project] = []
    @Published var agents: [String: [Agent]] = [:]
    @Published var messages: [String: [Message]] = [:]

    // MARK: - Connection

    @Published var isConnected: Bool = false

    // MARK: - Listeners

    private var projectsListener: ListenerRegistration?
    private var agentListeners: [String: ListenerRegistration] = [:]
    private var messageListeners: [String: ListenerRegistration] = [:]

    private let firebase = FirebaseManager.shared

    private init() {}

    // MARK: - Start/Stop Listening

    func startListening() {
        stopListening()

        guard let collection = firebase.projectsCollection() else { return }

        projectsListener = collection
            .order(by: "order")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let docs = snapshot?.documents else { return }

                Task { @MainActor in
                    self.projects = docs.compactMap { doc in
                        let d = doc.data()
                        return Project(
                            id: doc.documentID,
                            name: d["name"] as? String ?? "",
                            description: d["description"] as? String ?? "",
                            localPath: d["localPath"] as? String ?? "",
                            order: d["order"] as? Int ?? 0,
                            createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                        )
                    }
                    self.isConnected = true

                    // Start listening to agents for each project

                    for project in self.projects {
                        self.listenToAgents(projectId: project.id)
                    }
                }
            }
    }

    func stopListening() {
        projectsListener?.remove()
        projectsListener = nil

        for (_, listener) in agentListeners {
            listener.remove()
        }
        agentListeners.removeAll()

        for (_, listener) in messageListeners {
            listener.remove()
        }
        messageListeners.removeAll()
    }

    // MARK: - Agent Listeners

    private func listenToAgents(projectId: String) {
        agentListeners[projectId]?.remove()

        guard let collection = firebase.agentsCollection(projectId: projectId) else { return }

        agentListeners[projectId] = collection
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let docs = snapshot?.documents else { return }

                Task { @MainActor in
                    self.agents[projectId] = docs.compactMap { doc in
                        let d = doc.data()
                        return Agent(
                            id: doc.documentID,
                            projectId: projectId,
                            title: d["title"] as? String ?? "",
                            description: d["description"] as? String ?? "",
                            isDefault: d["isDefault"] as? Bool ?? false,
                            isFinished: d["isFinished"] as? Bool ?? false,
                            status: d["status"] as? String ?? "inactive",
                            createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                        )
                    }
                }
            }
    }

    // MARK: - Message Listeners

    func listenToMessages(agentId: String) {
        messageListeners[agentId]?.remove()

        guard let collection = firebase.messagesCollection(agentId: agentId) else { return }

        messageListeners[agentId] = collection
            .order(by: "timestamp")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let docs = snapshot?.documents else { return }

                Task { @MainActor in
                    self.messages[agentId] = docs.compactMap { doc in
                        let d = doc.data()
                        return Message(
                            id: doc.documentID,
                            agentId: d["agentId"] as? String ?? agentId,
                            role: d["role"] as? String ?? "user",
                            text: d["text"] as? String ?? "",
                            timestamp: (d["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                            persona: d["persona"] as? String ?? "agent"
                        )
                    }
                }
            }
    }

    func stopListeningToMessages(agentId: String) {
        messageListeners[agentId]?.remove()
        messageListeners.removeValue(forKey: agentId)
    }

    // MARK: - Send Message

    func sendMessage(agentId: String, projectId: String, text: String) async {

        // Optimistic local insert

        let localMsg = Message(agentId: agentId, role: "user", text: text)
        if messages[agentId] == nil { messages[agentId] = [] }
        messages[agentId]?.append(localMsg)

        // Write to Firestore (desktop will pick it up via listener)

        let data: [String: Any] = [
            "id": localMsg.id,
            "agentId": agentId,
            "role": "user",
            "text": text,
            "timestamp": FieldValue.serverTimestamp(),
            "persona": "agent",
            "source": "mobile"
        ]

        do {
            try await firebase.addMessage(data, agentId: agentId)
        } catch {
            print("Failed to send message: \(error)")
        }
    }

    // MARK: - Helpers

    func agentsForProject(_ projectId: String) -> [Agent] {
        agents[projectId] ?? []
    }

    func messagesForAgent(_ agentId: String) -> [Message] {
        messages[agentId] ?? []
    }
}
