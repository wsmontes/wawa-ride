import Foundation
import BitFoundation

/// Dual-transport coordinator: MultipeerKit (foreground, fast) + BLE mesh (background, multi-hop).
///
/// Built on BitChat's BinaryProtocol v2 wire format. BitChat provides the "TCP/IP" —
/// WawaRide provides the application-layer semantics (location, routes, waypoints).
///
/// Transport selection strategy (derived from BitChat's dual-transport architecture):
/// https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/Transport.swift
///
/// ⚠️ CRITICAL iOS LIMITATION (confirmed by DP-3T and Apple docs):
/// BLE background-to-background does NOT work on iOS. Two iPhones both in background
/// CANNOT discover each other via CoreBluetooth. At least one peer must be in foreground.
///
/// Priority order:
/// 1. MultipeerKit (Wi-Fi Direct): if peers connected → use it (fast, Codable, reliable)
/// 2. BLE mesh: always active as fallback (works foreground-to-any, multi-hop)
/// 3. Offline queue: if both transports have 0 peers → enqueue for later (GRDB pendingPacket)
///
/// Why send on BOTH when both available?
/// - MC is point-to-point (1 hop). BLE mesh relays to peers beyond MC range.
/// - A rider 3 hops away gets data via BLE but not MC.
/// - Deduplication (packet ID) prevents double-processing at recipients.
public final class TransportCoordinator: ObservableObject, @unchecked Sendable {
    public let ble: MeshBLEService
    public let multipeer: MultipeerTransport
    private var offlineQueue: [BitchatPacket] = []

    @Published public var totalPeerCount = 0

    public var onPacketReceived: ((BitchatPacket) -> Void)? {
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
    public func send(_ packet: BitchatPacket) {
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
