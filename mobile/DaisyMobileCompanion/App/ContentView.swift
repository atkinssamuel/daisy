import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        NavigationStack {
            ProjectsList()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataStore.shared)
}
