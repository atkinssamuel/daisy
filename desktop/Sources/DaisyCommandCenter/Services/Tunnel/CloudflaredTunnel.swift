import Foundation

// MARK: - Cloudflare Tunnel Manager

class CloudflaredTunnel: ObservableObject {
    static let shared = CloudflaredTunnel()

    @Published var tunnelURL: String?
    @Published var isRunning: Bool = false
    @Published var isInstalled: Bool = false

    private var process: Process?
    private var outputPipe: Pipe?

    private init() {
        isInstalled = checkInstalled()
    }

    // MARK: - Lifecycle

    func start(port: UInt16 = 9999) {
        guard !isRunning else { return }
        guard isInstalled else {
            print("cloudflared not installed — run: brew install cloudflared")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["cloudflared", "tunnel", "--url", "http://localhost:\(port)"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.outputPipe = pipe

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.tunnelURL = nil
            }
        }

        do {
            try proc.run()
            self.process = proc
            DispatchQueue.main.async { self.isRunning = true }

            // Read output in background to extract URL

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.readOutput(pipe: pipe)
            }
        } catch {
            print("Failed to start cloudflared: \(error)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        outputPipe = nil
        isRunning = false
        tunnelURL = nil
    }

    // MARK: - Output Parsing

    private func readOutput(pipe: Pipe) {
        let handle = pipe.fileHandleForReading

        while true {
            let data = handle.availableData
            if data.isEmpty { break }

            guard let output = String(data: data, encoding: .utf8) else { continue }

            // Extract the trycloudflare.com URL

            if let range = output.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression) {
                let url = String(output[range])
                DispatchQueue.main.async { [weak self] in
                    self?.tunnelURL = url
                    print("Tunnel URL: \(url)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkInstalled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", "cloudflared"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
