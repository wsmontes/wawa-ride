import Foundation
import Combine

// MARK: - Transport Manager

/// Orchestrates message delivery via mesh P2P + offline queue.
/// Zero server: the mesh IS the only transport.
/// Internet accelerates the mesh automatically (MultipeerConnectivity's WiFi infra relay).

@MainActor
final class TransportManager: ObservableObject {
    static let shared = TransportManager()

    private let mesh = MeshService.shared
    private let queue = OfflineQueue.shared

    @Published var transportState: TransportState = .idle

    enum TransportState {
        case idle
        case meshConnected
        case offline
    }

    private init() {}

    // MARK: - Send

    func send(_ payload: MeshPayload) {
        let strategy = bestStrategy(for: payload.priority)
        updateState()

        switch strategy {
        case .meshDirect:
            mesh.send(payload)

        case .meshWithQueue:
            mesh.send(payload)
            queue.enqueue(payload)

        case .queueOnly:
            queue.enqueue(payload)

        case .none:
            break  // Discard (expired/irrelevant data)
        }
    }

    // MARK: - Strategy

    private func bestStrategy(for priority: MeshPriority) -> TransportStrategy {
        let hasPeers = !mesh.connectedPeers.isEmpty

        switch priority {
        case .critical:
            return hasPeers ? .meshWithQueue : .queueOnly
        case .high:
            return hasPeers ? .meshWithQueue : .queueOnly
        case .normal:
            return hasPeers ? .meshDirect : .queueOnly
        case .low:
            return hasPeers ? .meshDirect : .none
        }
    }

    // MARK: - Drain

    func drainQueue() {
        let payloads = queue.drain(limit: 30)
        for payload in payloads {
            mesh.send(payload)
        }
    }

    func onConnectivityRestored() {
        updateState()
        drainQueue()
    }

    private func updateState() {
        if !mesh.connectedPeers.isEmpty {
            transportState = .meshConnected
        } else {
            transportState = .offline
        }
    }
}

// MARK: - Transport Strategy

enum TransportStrategy {
    case meshDirect      // Send now via mesh
    case meshWithQueue   // Send + persist in queue
    case queueOnly       // Only persist (offline)
    case none            // Discard
}

// MARK: - Offline Queue

final class OfflineQueue: @unchecked Sendable {
    static let shared = OfflineQueue()

    private let store = LocalStore.shared
    private let maxQueueSize = 1000

    private init() {}

    func enqueue(_ payload: MeshPayload) {
        do {
            try store.enqueue(payload)
        } catch {
            print("📮 OfflineQueue enqueue error: \(error)")
        }
    }

    func drain(limit: Int = 30) -> [MeshPayload] {
        store.drainQueue(limit: limit)
    }
}
