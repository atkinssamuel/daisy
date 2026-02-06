import SwiftUI

// MARK: - Settings Screen

struct SettingsScreen: View {
    @EnvironmentObject var store: DataStore
    @State private var serverAddress = AppConfig.serverAddress
    @State private var showSaved = false

    var body: some View {
        Form {
            Section("Connection") {
                HStack {
                    TextField("Server Address", text: $serverAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif

                    Button("Save") {
                        AppConfig.serverAddress = serverAddress
                        showSaved = true

                        Task {
                            await store.checkConnection()
                            if store.isConnected {
                                await store.fetchProjects()
                            }
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showSaved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(store.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)

                    Text(store.isConnected ? "Connected to \(serverAddress)" : "Not connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if showSaved {
                    Text("Settings saved")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Section("Info") {
                LabeledContent("Polling Interval", value: "\(Int(AppConfig.pollingInterval))s")
                LabeledContent("Projects Loaded", value: "\(store.projects.count)")
            }
        }
        .navigationTitle("Settings")
    }
}
