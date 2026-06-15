import Foundation
import MultipeerKit
import WawaMesh

/// MultipeerConnectivity transport (foreground, Wi-Fi Direct / Bluetooth Classic).
///
/// Complements BLE mesh: much faster throughput when in foreground + same network.
/// Uses MultipeerKit (insidegui/MultipeerKit, BSD-2, 1.1k stars):
/// https://github.com/insidegui/MultipeerKit
///
/// Why MultipeerKit over raw MultipeerConnectivity?
/// - Codable-based API (type-safe message passing, no raw Data wrangling)
/// - Targeted send (message specific peers, not just broadcast)
/// - SwiftUI-ready via MultipeerDataSource (@Published availablePeers)
/// - Testable (MockMultipeerConnection for unit tests)
/// - Handles session lifecycle, reconnection, invitation automatically
///
/// Why BOTH MultipeerKit AND BLE mesh?
/// - MultipeerKit uses Apple's MultipeerConnectivity framework (WiFi Direct + BT Classic)
/// - MC is FAST (Mbps) but only works in foreground and 1-hop (no multi-hop relay)
/// - BLE mesh is SLOW (Kbps) but works in background and supports multi-hop (TTL)
/// - During active ride (foreground): MC handles most traffic (fast, reliable)
/// - When app backgrounds or peers out of WiFi range: BLE mesh takes over
///
/// Reference: MultipeerKit's MultipeerTransceiver.swift for session management:
/// https://github.com/insidegui/MultipeerKit/blob/main/Sources/MultipeerKit/Public%20API/MultipeerTransceiver.swift
public final class MultipeerTransport: ObservableObject {
    private let transceiver: MultipeerTransceiver
    @Published public var connectedPeers: [Peer] = []

    public var onLocationReceived: ((LocationPayload, String) -> Void)?
    public var onSyncMessage: ((Data, String) -> Void)?

    public init() {
        var config = MultipeerConfiguration.default
        config.serviceType = "wawa-ride"       // Bonjour service type (max 15 chars)
        config.peerName = UIDevice.current.name
        config.security.encryptionPreference = .required
        transceiver = MultipeerTransceiver(configuration: config)

        transceiver.availablePeersDidChange = { [weak self] peers in
            DispatchQueue.main.async { self?.connectedPeers = peers }
        }

        // Type-safe receivers via MultipeerKit's Codable dispatch
        transceiver.receive(LocationPayload.self) { [weak self] payload, peer in
            self?.onLocationReceived?(payload, peer.name)
        }
        transceiver.receive(SyncEnvelope.self) { [weak self] envelope, peer in
            self?.onSyncMessage?(envelope.data, peer.name)
        }
    }

    public func start() { transceiver.resume() }
    public func stop() { transceiver.stop() }

    /// Broadcast location to all connected MC peers (Codable, fast).
    public func broadcastLocation(_ payload: LocationPayload) {
        transceiver.broadcast(payload)
    }

    /// Send Automerge sync data to a specific peer.
    public func sendSync(_ data: Data, to peer: Peer) {
        transceiver.send(SyncEnvelope(data: data), to: [peer])
    }

    /// Broadcast Automerge sync data to all MC peers.
    public func broadcastSync(_ data: Data) {
        transceiver.broadcast(SyncEnvelope(data: data))
    }
}

/// Wrapper for Automerge sync bytes — MultipeerKit requires Codable for dispatch.
struct SyncEnvelope: Codable {
    let data: Data
}
