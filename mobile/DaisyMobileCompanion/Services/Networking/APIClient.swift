import Foundation

// MARK: - API Client

class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: URL

    private init() {
        self.session = URLSession.shared
        self.baseURL = URL(string: AppConfig.apiBaseURL)!
    }

    // MARK: - Generic Request

    func request<T: Decodable>(_ endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
        var url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - API Errors

enum APIError: Error, LocalizedError {
    case requestFailed
    case decodingFailed
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Request failed"
        case .decodingFailed:
            return "Failed to decode response"
        case .unauthorized:
            return "Unauthorized"
        }
    }
}
