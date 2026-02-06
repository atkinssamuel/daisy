import Foundation

/// Application configuration and secrets
struct AppConfig {
    // MARK: - Gateway Configuration
    static let gatewayHost = ProcessInfo.processInfo.environment["DAISY_GATEWAY_HOST"] ?? "127.0.0.1"
    static let gatewayPort = ProcessInfo.processInfo.environment["DAISY_GATEWAY_PORT"] ?? "18789"
    static let gatewayURL = "http://\(gatewayHost):\(gatewayPort)/v1/chat/completions"

    static let gatewayToken = ProcessInfo.processInfo.environment["DAISY_GATEWAY_TOKEN"]
        ?? "04ffa0dab64b10d0d0700f43fb8751d5aa6a1f63a9dacf24a6ab3a550a41928c"

    // MARK: - Server Configuration
    static let mcpServerPort: UInt16 = 9999
    static let toolExecutionIterationLimit = 10

    // MARK: - Database Configuration
    static let databaseFileName = "daisy.db"

    // MARK: - Feature Flags
    static let enableDebugLogging = ProcessInfo.processInfo.environment["DAISY_DEBUG"] == "1"
}
