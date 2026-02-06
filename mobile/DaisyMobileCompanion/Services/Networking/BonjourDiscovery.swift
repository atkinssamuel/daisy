import Foundation
import Network

// MARK: - Bonjour Discovery

@MainActor
class BonjourDiscovery: ObservableObject {
    static let shared = BonjourDiscovery()

    @Published var discoveredHost: String?
    @Published var isSearching: Bool = false

    private var browser: NWBrowser?

    private init() {}

    // MARK: - Start/Stop

    func startSearching() {
        stopSearching()
        isSearching = true

        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_daisy._tcp.", domain: nil), using: params)

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .failed:
                    self?.isSearching = false
                case .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.handleResults(results)
            }
        }

        browser?.start(queue: .main)
    }

    func stopSearching() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    // MARK: - Handle Results

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        guard let result = results.first else {
            discoveredHost = nil
            return
        }

        // Resolve the endpoint to get the actual IP

        let connection = NWConnection(to: result.endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if let endpoint = connection.currentPath?.remoteEndpoint {
                    let hostString = extractBonjourHost(from: endpoint)
                    DispatchQueue.main.async {
                        if let host = hostString {
                            self?.discoveredHost = "\(host):9999"
                        }
                    }
                }
                connection.cancel()
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }
}

// MARK: - Host Extraction (nonisolated)

private func extractBonjourHost(from endpoint: NWEndpoint) -> String? {
    switch endpoint {
    case .hostPort(let host, _):
        switch host {
        case .ipv4(let addr):
            return "\(addr)"
        case .ipv6(let addr):
            return "\(addr)"
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    default:
        return nil
    }
}
