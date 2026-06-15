import Foundation

/// Dual-transport coordinator: MultipeerKit (foreground, fast) + BLE mesh (background, multi-hop).
///
/// Transport selection strategy (derived from BitChat's dual-transport architecture):
/// https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/Transport.swift
///
/// Priority order:
/// 1. MultipeerKit (Wi-Fi Direct): if peers connected → use it (fast, Codable, reliable)
/// 2. BLE mesh: always active as fallback (works in background, multi-hop)
/// 3. Offline queue: if both transports have 0 peers → enqueue for later
///
/// In practice during a ride:
/// - Foreground: both MC and BLE are active. Location goes via MC (fast) AND BLE (resilient).
/// - Background: only BLE active (MC dies when backgrounded). BLE handles location relay.
/// - No peers at all: packets queue in GRDB's pendingPacket table until connectivity returns.
///
/// Why send on BOTH when both available?
/// - MC is point-to-point (1 hop). BLE mesh relays to peers beyond MC range.
/// - A rider 3 hops away gets data via BLE but not MC.
/// - Deduplication (MeshPacket.messageID) prevents double-processing at recipients.
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

    /// Send mesh packet via BLE (multi-hop capable, background-safe).
    public func send(_ packet: MeshPacket) {
        if ble.connectedPeerCount > 0 {
            ble.broadcast(packet)
        } else {
            offlineQueue.append(packet)
        }
    }

    /// Send location via MultipeerKit (fast Codable path, foreground only).
    public func broadcastLocation(_ payload: LocationPayload) {
        multipeer.broadcastLocation(payload)
    }

    /// Send Automerge sync data via MultipeerKit (CRDT reconciliation).
    public func broadcastSync(_ data: Data) {
        multipeer.broadcastSync(data)
    }

    /// Flush queued packets when connectivity returns.
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
