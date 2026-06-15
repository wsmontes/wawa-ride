import Foundation

/// Transport selection: BLE first, Nostr fallback, queue if both offline.
public final class TransportCoordinator: ObservableObject, @unchecked Sendable {
    public let ble: MeshBLEService
    private var offlineQueue: [MeshPacket] = []

    public var onPacketReceived: ((MeshPacket) -> Void)? {
        didSet { ble.onPacketReceived = onPacketReceived }
    }

    public init(ble: MeshBLEService = MeshBLEService()) {
        self.ble = ble
    }

    public func start() { ble.start() }
    public func stop() { ble.stop() }

    public func send(_ packet: MeshPacket) {
        if ble.connectedPeerCount > 0 {
            ble.broadcast(packet)
        } else {
            offlineQueue.append(packet)
        }
    }

    public func flushQueue() {
        let queued = offlineQueue
        offlineQueue.removeAll()
        for packet in queued { send(packet) }
    }
}
