import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var firebase: FirebaseManager

    var body: some View {
        if firebase.isSignedIn {
            mainContent
        } else {
            AuthView()
        }
    }

    private var mainContent: some View {
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
            store.startListening()
        }
        .onDisappear {
            store.stopListening()
        }
    }
}
