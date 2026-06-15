import Foundation
import MultipeerKit
import WawaMesh

/// MultipeerConnectivity transport (foreground, Wi-Fi Direct / Bluetooth Classic).
/// Complements BLE mesh: faster throughput when in foreground + same network.
public final class MultipeerTransport: ObservableObject {
    private let transceiver: MultipeerTransceiver
    @Published public var connectedPeers: [Peer] = []

    public var onLocationReceived: ((LocationPayload, String) -> Void)?
    public var onSyncMessage: ((Data, String) -> Void)?

    public init() {
        var config = MultipeerConfiguration.default
        config.serviceType = "wawa-ride"
        config.peerName = UIDevice.current.name
        config.security.encryptionPreference = .required
        transceiver = MultipeerTransceiver(configuration: config)

        transceiver.availablePeersDidChange = { [weak self] peers in
            DispatchQueue.main.async { self?.connectedPeers = peers }
        }

        // Receive location updates via MultipeerKit (Codable)
        transceiver.receive(LocationPayload.self) { [weak self] payload, peer in
            self?.onLocationReceived?(payload, peer.name)
        }

        // Receive Automerge sync messages
        transceiver.receive(SyncEnvelope.self) { [weak self] envelope, peer in
            self?.onSyncMessage?(envelope.data, peer.name)
        }
    }

    public func start() { transceiver.resume() }
    public func stop() { transceiver.stop() }

    public func broadcastLocation(_ payload: LocationPayload) {
        transceiver.broadcast(payload)
    }

    public func sendSync(_ data: Data, to peer: Peer) {
        transceiver.send(SyncEnvelope(data: data), to: [peer])
    }

    public func broadcastSync(_ data: Data) {
        transceiver.broadcast(SyncEnvelope(data: data))
    }
}

/// Wrapper for Automerge sync data (MultipeerKit requires Codable).
struct SyncEnvelope: Codable {
    let data: Data
}
