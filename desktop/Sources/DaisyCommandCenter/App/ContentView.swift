import SwiftUI

// MARK: - Main View

struct ContentView: View {
    @ObservedObject private var store: DataStore
    @ObservedObject private var firebase = FirebaseManager.shared

    init() {
        _store = ObservedObject(wrappedValue: DataStore.shared)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if firebase.isSignedIn {
                mainContent
            } else {
                AuthView()
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .transaction { $0.animation = nil }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {

            // Left: Projects sidebar

            ProjectsSidebar()
                .frame(width: 180)
                .background(Color(white: 0.08))

            Divider().background(Color(white: 0.2))

            // Middle: Agents list

            AgentsList()
                .frame(width: 240)
                .background(Color(white: 0.06))

            Divider().background(Color(white: 0.2))

            // Right: Agent detail / Chat

            AgentDetail()
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.04))
        }
        .environmentObject(store)
        .onAppear {}
        .sheet(isPresented: $store.showProjectSettings) {
            ProjectSettingsSheet()
                .environmentObject(store)
        }
    }
}
