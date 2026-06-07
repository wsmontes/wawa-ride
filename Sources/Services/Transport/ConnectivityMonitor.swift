import Foundation
import Network

// MARK: - Connectivity Monitor

@MainActor
final class ConnectivityMonitor: ObservableObject {
    static let shared = ConnectivityMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.wawa.connectivity")

    @Published var hasInternet = false
    @Published var connectionType = "unknown"
    @Published var isExpensive = false
    @Published var isConstrained = false

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.hasInternet = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained

                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = "wifi"
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = "cellular"
                } else {
                    self?.connectionType = "other"
                }

                // Notify transport manager of connectivity change
                if path.status == .satisfied {
                    TransportManager.shared.onConnectivityRestored()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
