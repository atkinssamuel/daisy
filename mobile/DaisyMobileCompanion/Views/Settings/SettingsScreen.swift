import SwiftUI

// MARK: - Settings Screen

struct SettingsScreen: View {
    @EnvironmentObject var store: DataStore
    @ObservedObject private var firebase = FirebaseManager.shared

    var body: some View {
        Form {
            Section("Account") {
                if let email = firebase.userEmail {
                    LabeledContent("Email", value: email)
                }

                LabeledContent("Projects", value: "\(store.projects.count)")

                Button("Sign Out", role: .destructive) {
                    store.stopListening()
                    try? firebase.signOut()
                }
            }

            Section("Info") {
                LabeledContent("Sync", value: "Real-time (Firestore)")
                LabeledContent("Auth", value: "Firebase Auth")
            }
        }
        .navigationTitle("Settings")
    }
}
