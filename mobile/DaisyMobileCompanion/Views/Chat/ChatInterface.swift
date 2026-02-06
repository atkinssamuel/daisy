import SwiftUI

// MARK: - Chat Interface

struct ChatInterface: View {
    @EnvironmentObject var store: DataStore
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {

            // Messages area

            ScrollView {
                LazyVStack(spacing: 12) {
                    Text("Chat coming soon")
                        .foregroundColor(.secondary)
                }
                .padding()
            }

            Divider()

            // Input bar

            HStack(spacing: 12) {
                TextField("Message...", text: $inputText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
    }
}
