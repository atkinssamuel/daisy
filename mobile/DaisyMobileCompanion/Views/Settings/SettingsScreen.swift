import SwiftUI

// MARK: - Settings Screen

struct SettingsScreen: View {
    @EnvironmentObject var store: DataStore
    @StateObject private var discovery = BonjourDiscovery.shared
    @State private var serverAddress = AppConfig.serverAddress
    @State private var tunnelURL = AppConfig.tunnelURL ?? ""
    @State private var connectionMode: ConnectionMode = AppConfig.tunnelURL != nil ? .remote : .local
    @State private var showSaved = false

    enum ConnectionMode: String, CaseIterable {
        case local = "Local (Wi-Fi)"
        case remote = "Remote (Tunnel)"
    }

    var body: some View {
        Form {

            // Connection mode picker

            Section("Connection Mode") {
                Picker("Mode", selection: $connectionMode) {
                    ForEach(ConnectionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: connectionMode) { _, newMode in
                    switch newMode {
                    case .local:
                        AppConfig.tunnelURL = nil
                    case .remote:
                        if !tunnelURL.isEmpty {
                            AppConfig.tunnelURL = tunnelURL
                        }
                    }
                    reconnect()
                }
            }

            if connectionMode == .local {

                // Local connection

                Section("Local Network") {
                    HStack {
                        TextField("Server Address", text: $serverAddress)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif

                        Button("Save") {
                            AppConfig.serverAddress = serverAddress
                            AppConfig.tunnelURL = nil
                            showSaved = true
                            reconnect()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    // Auto-discovery

                    if discovery.isSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching local network...")
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
                                AppConfig.serverAddress = host
                                AppConfig.tunnelURL = nil
                                reconnect()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

            } else {

                // Remote tunnel

                Section("Remote Tunnel") {
                    TextField("Tunnel URL", text: $tunnelURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif

                    Button("Connect") {
                        let url = tunnelURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        AppConfig.tunnelURL = url.isEmpty ? nil : url
                        showSaved = true
                        reconnect()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Get the tunnel URL from your desktop app's settings or the /health endpoint.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Status

            Section("Status") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)

                    Text(store.isConnected ? "Connected" : "Not connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                LabeledContent("Endpoint", value: AppConfig.baseURL)
                    .font(.caption)

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
        .onAppear {
            discovery.startSearching()
        }
        .onDisappear {
            discovery.stopSearching()
        }
    }

    private func reconnect() {
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
