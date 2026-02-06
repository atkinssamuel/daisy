import Foundation

struct AppConfig {

    // Server address stored in UserDefaults

    static var serverAddress: String {
        get { UserDefaults.standard.string(forKey: "serverAddress") ?? "127.0.0.1:9999" }
        set { UserDefaults.standard.set(newValue, forKey: "serverAddress") }
    }

    // Tunnel URL for remote access (persisted)

    static var tunnelURL: String? {
        get { UserDefaults.standard.string(forKey: "tunnelURL") }
        set { UserDefaults.standard.set(newValue, forKey: "tunnelURL") }
    }

    // Use tunnel URL if available and not on local network

    static var baseURL: String {
        if let tunnel = tunnelURL, !tunnel.isEmpty {
            return tunnel
        }
        return "http://\(serverAddress)"
    }

    static let pollingInterval: TimeInterval = 2.0
}
