import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DataStore
    @StateObject private var discovery = BonjourDiscovery.shared

    var body: some View {
        TabView {
            NavigationStack {
                ProjectsList()
            }
            .tabItem {
                Label("Projects", systemImage: "folder.fill")
            }

            NavigationStack {
                SettingsScreen()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .onAppear {
            discovery.startSearching()

            Task {
                // Wait briefly for Bonjour discovery

                try? await Task.sleep(nanoseconds: 1_500_000_000)

                if let host = discovery.discoveredHost, !store.isConnected {
                    AppConfig.serverAddress = host
                }

                await store.checkConnection()
                await store.fetchProjects()
                store.startPolling()
            }
        }
    }
}
