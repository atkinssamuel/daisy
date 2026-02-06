import Foundation

// MARK: - App Configuration

struct AppConfig {

    // MARK: - API Configuration

    static let apiBaseURL = ProcessInfo.processInfo.environment["DAISY_API_URL"]
        ?? "http://127.0.0.1:9999"

    // MARK: - Feature Flags

    static let enableDebugLogging = ProcessInfo.processInfo.environment["DAISY_DEBUG"] == "1"
}
