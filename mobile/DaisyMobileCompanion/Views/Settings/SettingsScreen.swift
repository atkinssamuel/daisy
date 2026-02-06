import SwiftUI

// MARK: - Settings Screen

struct SettingsScreen: View {
    @EnvironmentObject var store: DataStore
    @StateObject private var discovery = BonjourDiscovery.shared
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
                        saveAndConnect()
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

            // Auto-Discovery

            Section("Auto-Discovery") {
                if discovery.isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching for Daisy on your network...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                if let host = discovery.discoveredHost {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Daisy Command Center")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(host)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Connect") {
                            serverAddress = host
                            saveAndConnect()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else if !discovery.isSearching {
                    Button {
                        discovery.startSearching()
                    } label: {
                        Label("Search for Desktop", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }

            Section("Info") {
                LabeledContent("Polling Interval", value: "\(Int(AppConfig.pollingInterval))s")
                LabeledContent("Projects Loaded", value: "\(store.projects.count)")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            discovery.startSearching()
        }
        .onDisappear {
            discovery.stopSearching()
        }
    }

    private func saveAndConnect() {
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
}
