import SwiftUI
import FirebaseCore

@main
struct DaisyMobileApp: App {
    @StateObject private var store = DataStore.shared
    @StateObject private var firebase = FirebaseManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(firebase)
                .preferredColorScheme(.dark)
        }
    }
}
