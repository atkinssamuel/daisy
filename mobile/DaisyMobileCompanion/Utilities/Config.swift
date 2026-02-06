import Foundation

struct AppConfig {

    // Server address stored in UserDefaults

    static var serverAddress: String {
        get { UserDefaults.standard.string(forKey: "serverAddress") ?? "127.0.0.1:9999" }
        set { UserDefaults.standard.set(newValue, forKey: "serverAddress") }
    }

    static var baseURL: String {
        "http://\(serverAddress)"
    }

    static let pollingInterval: TimeInterval = 2.0
}
