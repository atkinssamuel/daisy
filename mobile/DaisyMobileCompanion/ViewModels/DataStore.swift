import Foundation
import Combine

// MARK: - App-Wide Data Store

@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()

    // MARK: - Data

    @Published var projects: [Project] = []
    @Published var agents: [String: [Agent]] = [:]
    @Published var messages: [String: [Message]] = [:]

    // MARK: - Connection

    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false

    // MARK: - Polling

    private var pollTimer: Timer?
    private let api = APIClient.shared

    private init() {}

    // MARK: - Connection

    func checkConnection() async {
        let connected = await api.healthCheck()
        isConnected = connected
    }

    // MARK: - Polling Lifecycle

    func startPolling() {
        stopPolling()

        pollTimer = Timer.scheduledTimer(withTimeInterval: AppConfig.pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollStatus()
            }
        }

        // Immediate first poll

        Task {
            await pollStatus()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Fetch Projects

    func fetchProjects() async {
        do {
            projects = try await api.getProjects()
        } catch {
            print("✗ Failed to fetch projects: \(error)")
        }
    }

    // MARK: - Fetch Agents

    func fetchAgents(projectId: String) async {
        do {
            let fetched = try await api.getAgents(projectId: projectId)
            agents[projectId] = fetched
        } catch {
            print("✗ Failed to fetch agents: \(error)")
        }
    }

    // MARK: - Fetch Messages

    func fetchMessages(agentId: String) async {
        do {
            let fetched = try await api.getMessages(agentId: agentId)
            messages[agentId] = fetched
        } catch {
            print("✗ Failed to fetch messages: \(error)")
        }
    }

    // MARK: - Send Message

    func sendMessage(agentId: String, projectId: String, text: String) async {
        // Optimistic local insert

        let localMsg = Message(agentId: agentId, role: "user", text: text)
        if messages[agentId] == nil { messages[agentId] = [] }
        messages[agentId]?.append(localMsg)

        do {
            try await api.sendMessage(agentId: agentId, projectId: projectId, text: text)
        } catch {
            print("✗ Failed to send message: \(error)")
        }
    }

    // MARK: - Poll Status

    func pollStatus() async {
        do {
            let status = try await api.getStatus()
            isConnected = true

            // Update projects from status

            for projectStatus in status.projects {
                if let idx = projects.firstIndex(where: { $0.id == projectStatus.id }) {
                    projects[idx].agentCount = projectStatus.agents.count
                    projects[idx].activeAgentCount = projectStatus.agents.filter { $0.isThinking }.count
                }

                // Update agent live status

                if var agentList = agents[projectStatus.id] {
                    for agentStatus in projectStatus.agents {
                        if let agentIdx = agentList.firstIndex(where: { $0.id == agentStatus.id }) {
                            agentList[agentIdx].isThinking = agentStatus.isThinking
                            agentList[agentIdx].focus = agentStatus.focus
                            agentList[agentIdx].sessionRunning = agentStatus.sessionRunning
                        }
                    }
                    agents[projectStatus.id] = agentList
                }
            }
        } catch {
            isConnected = false
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
