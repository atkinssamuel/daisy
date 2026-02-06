import SwiftUI
import Combine

// MARK: - Terminal Pane (output only, no input)
// Shows live tmux terminal output with ANSI color rendering

struct TerminalPane: View {
    @ObservedObject var viewModel: TerminalViewModel

    var body: some View {
        VStack(spacing: 0) {

            // Minimal header

            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)

                Text("Terminal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                if let session = viewModel.session {
                    Circle()
                        .fill(session.isRunning ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.06))

            Divider().background(Color(white: 0.15))

            // Terminal output

            TerminalTextView(attributedString: viewModel.attributedOutput)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// -------------------------------------------------------------------------------------
// ----------------------------------- Registry ----------------------------------------
// -------------------------------------------------------------------------------------

// MARK: - Terminal View Model Registry
// Maintains one TerminalViewModel per session ID, all polling independently.
// Switching personas just swaps which view model the UI observes — no reset.

@MainActor
class TerminalViewModelRegistry: ObservableObject {
    static let shared = TerminalViewModelRegistry()

    private var viewModels: [String: TerminalViewModel] = [:]

    private init() {}

    func viewModel(for sessionId: String, session: ClaudeCodeSession, store: DataStore) -> TerminalViewModel {
        if let existing = viewModels[sessionId] {

            // Keep store reference fresh

            existing.store = store
            return existing
        }

        let vm = TerminalViewModel(session: session, store: store)
        viewModels[sessionId] = vm
        return vm
    }

    func remove(sessionId: String) {
        viewModels[sessionId]?.stopPolling()
        viewModels.removeValue(forKey: sessionId)
    }
}

// -------------------------------------------------------------------------------------
// ----------------------------------- View Model --------------------------------------
// -------------------------------------------------------------------------------------

// MARK: - Terminal View Model
// Polls a single tmux session independently. Tracks thinking state continuously.

@MainActor
class TerminalViewModel: ObservableObject {
    @Published var attributedOutput = NSAttributedString()
    var session: ClaudeCodeSession?
    weak var store: DataStore?

    private var timer: AnyCancellable?
    private var previousHash: Int = 0

    init(session: ClaudeCodeSession, store: DataStore) {
        self.session = session
        self.store = store
        startPolling()
    }

    func startPolling() {
        timer?.cancel()
        timer = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.poll()
            }
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    func clearThinking() {

        // Clear MCP typing indicator

        if let sessionId = session?.id {
            MCPServer.shared.setTyping(sessionId: sessionId, typing: false)
        }
    }

    private func poll() {
        guard let session = session, session.isRunning else { return }

        let capturedSession = session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let raw = capturedSession.capturePane()
            let parsed = ANSIParser.parse(raw)

            // Strip ANSI escapes for change detection — cursor/color changes don't count

            let stripped = raw.replacingOccurrences(of: "\\x1b\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hash = stripped.hashValue

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if hash != self.previousHash {
                    self.previousHash = hash
                    self.attributedOutput = parsed
                }
            }
        }
    }

    // Called externally when the user sends a message

    func userDidSend() {

        // Typing indicator is now managed by MCP send_message --done flag

    }

    deinit {
        timer?.cancel()
    }
}
