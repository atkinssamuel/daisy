import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DataStore

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
            Task {
                await store.checkConnection()
                await store.fetchProjects()
                store.startPolling()
            }
        }
    }
}
