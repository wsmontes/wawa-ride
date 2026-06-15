import Foundation

/// Dual-transport coordinator: MultipeerKit (foreground, fast) + BLE mesh (background, multi-hop).
/// Sends via whichever is available; queues if both offline.
public final class TransportCoordinator: ObservableObject, @unchecked Sendable {
    public let ble: MeshBLEService
    public let multipeer: MultipeerTransport
    private var offlineQueue: [MeshPacket] = []

    @Published public var totalPeerCount = 0

    public var onPacketReceived: ((MeshPacket) -> Void)? {
        didSet { ble.onPacketReceived = onPacketReceived }
    }
    public var onLocationReceived: ((LocationPayload, String) -> Void)? {
        didSet { multipeer.onLocationReceived = onLocationReceived }
    }
    public var onSyncMessage: ((Data, String) -> Void)? {
        didSet { multipeer.onSyncMessage = onSyncMessage }
    }

    public init() {
        ble = MeshBLEService()
        multipeer = MultipeerTransport()
        ble.onPeerCountChanged = { [weak self] _ in self?.updateCount() }
    }

    public func start() {
        ble.start()
        multipeer.start()
        flushQueue()
    }

    public func stop() {
        ble.stop()
        multipeer.stop()
    }

    /// Send mesh packet via BLE (multi-hop, background-capable).
    public func send(_ packet: MeshPacket) {
        if ble.connectedPeerCount > 0 {
            ble.broadcast(packet)
        } else {
            offlineQueue.append(packet)
        }
    }

    /// Send location via MultipeerKit (fast, foreground only).
    public func broadcastLocation(_ payload: LocationPayload) {
        multipeer.broadcastLocation(payload)
    }

    /// Send Automerge sync data via MultipeerKit.
    public func broadcastSync(_ data: Data) {
        multipeer.broadcastSync(data)
    }

    public func flushQueue() {
        let queued = offlineQueue
        offlineQueue.removeAll()
        for packet in queued { send(packet) }
    }

    private func updateCount() {
        DispatchQueue.main.async {
            self.totalPeerCount = self.ble.connectedPeerCount + self.multipeer.connectedPeers.count
        }
    }
}
