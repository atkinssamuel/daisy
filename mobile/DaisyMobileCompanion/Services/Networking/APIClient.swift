import Foundation

// MARK: - API Client

class APIClient {
    static let shared = APIClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    private var baseURL: String { AppConfig.baseURL }

    // MARK: - Health Check

    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }

        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Projects

    func getProjects() async throws -> [Project] {
        let response: ProjectsResponse = try await get("/api/projects")
        return response.projects
    }

    // MARK: - Agents

    func getAgents(projectId: String) async throws -> [Agent] {
        let response: AgentsResponse = try await get("/api/projects/\(projectId)/agents")
        return response.agents
    }

    // MARK: - Messages

    func getMessages(agentId: String, limit: Int = 50) async throws -> [Message] {
        let response: MessagesResponse = try await get("/api/agents/\(agentId)/messages?limit=\(limit)")
        return response.messages
    }

    // MARK: - Send Message

    func sendMessage(agentId: String, projectId: String, text: String) async throws {
        let body: [String: Any] = ["message": text, "projectId": projectId]
        let _: SendResponse = try await post("/api/agents/\(agentId)/send", body: body)
    }

    // MARK: - Status Polling

    func getStatus() async throws -> StatusResponse {
        try await get("/api/status")
    }

    // MARK: - Generic Requests

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Response Types

struct ProjectsResponse: Codable {
    let projects: [Project]
}

struct AgentsResponse: Codable {
    let agents: [Agent]
}

struct MessagesResponse: Codable {
    let messages: [Message]
}

struct SendResponse: Codable {
    let success: Bool
}

struct StatusResponse: Codable {
    let projects: [ProjectStatus]

    struct ProjectStatus: Codable, Identifiable {
        let id: String
        let name: String
        let agents: [AgentStatus]
    }

    struct AgentStatus: Codable, Identifiable {
        let id: String
        let title: String
        let isDefault: Bool
        let isThinking: Bool
        let focus: String?
        let sessionRunning: Bool
    }
}

// MARK: - API Errors

enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .requestFailed: return "Request failed"
        case .decodingFailed: return "Failed to decode response"
        }
    }
}
