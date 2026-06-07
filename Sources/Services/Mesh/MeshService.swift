import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Mesh Service (Orchestrator)

@MainActor
final class MeshService: NSObject, ObservableObject {
    static let shared = MeshService()

    static let serviceType = "wawa-ride"

    // Core
    let myPeerID: MCPeerID
    let session: MCSession

    // Sub-components
    let advertiser: MeshAdvertiser
    let browser: MeshBrowser
    let relay: MeshRelay

    // State
    @Published var connectedPeers: [MCPeerID] = []
    @Published var discoveredRides: [DiscoveredRide] = []
    @Published var meshState: MeshState = .idle

    // Current ride
    private var currentRideId: String?
    private var currentRiderName: String = ""

    // Auto-presence (always-on discovery)
    private var isAutoPresenceActive = false
    let presenceId: String

    // Callbacks
    var onPayloadReceived: ((MeshPayload) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?

    enum MeshState {
        case idle
        case advertising
        case browsing
        case connected
    }

    struct DiscoveredRide: Identifiable {
        let id: String          // rideId
        let peerID: MCPeerID
        let rideName: String
        let leaderName: String
        let riderCount: Int
        let rideStatus: String
        let roomCount: Int
    }

    override init() {
        let deviceName = UIDevice.current.name
        myPeerID = MCPeerID(displayName: deviceName)

        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        advertiser = MeshAdvertiser(peerID: myPeerID, serviceType: Self.serviceType)
        browser = MeshBrowser(peerID: myPeerID, serviceType: Self.serviceType)
        relay = MeshRelay()

        // Unique presence ID (persists across app launches)
        if let saved = UserDefaults.standard.string(forKey: "presenceId") {
            presenceId = saved
        } else {
            presenceId = UUID().uuidString
            UserDefaults.standard.set(presenceId, forKey: "presenceId")
        }

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    // MARK: - Auto-Presence (always-on discovery)

    /// Start advertising AND browsing simultaneously.
    /// Any two devices with the app open will discover each other automatically.
    func startAutoPresence(name: String) {
        guard !isAutoPresenceActive else { return }
        isAutoPresenceActive = true
        currentRiderName = name

        let info = MeshDiscoveryInfo(
            rideId: presenceId,
            rideName: name,
            leaderName: name,
            riderCount: "1",
            rideStatus: "presence",
            roomCount: "0",
            version: "2"
        )

        advertiser.start(with: info)
        browser.start()
        meshState = .browsing
    }

    func stopAutoPresence() {
        isAutoPresenceActive = false
        advertiser.stop()
        browser.stop()
    }

    var hasNearbyPeers: Bool {
        !connectedPeers.isEmpty
    }

    // MARK: - Lifecycle

    func startAdvertising(rideId: String, rideName: String, leaderName: String, riderCount: Int, roomCount: Int) {
        currentRideId = rideId
        currentRiderName = leaderName
        meshState = .advertising

        let info = MeshDiscoveryInfo(
            rideId: rideId,
            rideName: rideName,
            leaderName: leaderName,
            riderCount: String(riderCount),
            rideStatus: "active",
            roomCount: String(roomCount),
            version: "2"
        )

        advertiser.start(with: info)
    }

    func startBrowsing() {
        meshState = .browsing
        browser.start()
    }

    func stopAdvertising() {
        advertiser.stop()
    }

    func stopBrowsing() {
        browser.stop()
    }

    func leaveMesh() {
        advertiser.stop()
        browser.stop()
        session.disconnect()
        connectedPeers.removeAll()
        meshState = .idle
        currentRideId = nil
    }

    // MARK: - Connection

    func invitePeer(_ peerID: MCPeerID) {
        browser.invite(peerID, to: session)
    }

    // MARK: - Sending

    func send(_ payload: MeshPayload) {
        guard !session.connectedPeers.isEmpty else { return }

        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(payload)
        } catch {
            print("🔗 Mesh encode error: \(error)")
            return
        }

        do {
            try session.send(encoded, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("🔗 Mesh send error: \(error)")
        }
    }

    func sendToPeer(_ payload: MeshPayload, peer: MCPeerID) {
        do {
            let encoded = try JSONEncoder().encode(payload)
            try session.send(encoded, toPeers: [peer], with: .reliable)
        } catch {
            print("🔗 Mesh sendToPeer error: \(error)")
        }
    }

    func startVoiceStream(to peerID: MCPeerID, roomId: String) throws -> OutputStream {
        let streamName = "wawa-voice-\(roomId)"
        return try session.startStream(withName: streamName, toPeer: peerID)
    }

    // MARK: - Incoming

    private func handleReceivedData(_ data: Data, from peerID: MCPeerID) {
        guard let payload = try? JSONDecoder().decode(MeshPayload.self, from: data) else {
            print("🔗 Mesh decode error")
            return
        }

        // Dedup
        guard !relay.hasSeen(payload.id) else { return }
        relay.markSeen(payload.id)

        // Dispatch to handler
        onPayloadReceived?(payload)

        // Forward with TTL-1 if applicable
        var forwardPayload = payload
        forwardPayload.ttl -= 1
        guard forwardPayload.ttl > 0 else { return }

        let forwardTo = session.connectedPeers.filter { $0 != peerID }
        guard !forwardTo.isEmpty else { return }

        do {
            let encoded = try JSONEncoder().encode(forwardPayload)
            try session.send(encoded, toPeers: forwardTo, with: .reliable)
        } catch {
            print("🔗 Mesh forward error: \(error)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MeshService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(where: { $0.displayName == peerID.displayName }) {
                    self.connectedPeers.append(peerID)
                }
                self.meshState = .connected
                self.onPeerConnected?(peerID)
                NotificationCenter.default.post(name: .meshPeerConnected, object: peerID)

                // MCSession is the continuous channel — BLE → WiFi Direct → WiFi Infra
                // Data flows automatically. No separate relay needed.

            case .notConnected:
                self.connectedPeers.removeAll { $0.displayName == peerID.displayName }
                self.onPeerDisconnected?(peerID)
                NotificationCenter.default.post(name: .meshPeerDisconnected, object: peerID)

                // MCSession will auto-reconnect when back in range

            case .connecting:
                break

            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.handleReceivedData(data, from: peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Voice stream received — handled by VoiceChatService
        NotificationCenter.default.post(
            name: .meshVoiceStreamReceived,
            object: nil,
            userInfo: ["stream": stream, "streamName": streamName, "peerID": peerID]
        )
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in MVP
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in MVP
    }
}

// MARK: - MeshAdvertiserDelegate

extension MeshService: MeshAdvertiserDelegate {
    func advertiser(_ advertiser: MeshAdvertiser, didReceiveInvitationFrom peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept in MVP by providing our session
        invitationHandler(true, session)
    }
}

// MARK: - MeshBrowserDelegate

extension MeshService: MeshBrowserDelegate {
    func browser(_ browser: MeshBrowser, didFind peerID: MCPeerID, with discoveryInfo: [String: String]?) {
        guard let info = MeshDiscoveryInfo.from(discoveryInfo) else { return }

        // Don't connect to self
        if info.rideId == presenceId || info.rideId == currentRideId { return }

        // Auto-invite: connect immediately when we find another presence
        if isAutoPresenceActive && !connectedPeers.contains(where: { $0.displayName == peerID.displayName }) {
            browser.invite(peerID, to: session)
        }

        let ride = DiscoveredRide(
            id: info.rideId,
            peerID: peerID,
            rideName: info.rideName,
            leaderName: info.leaderName,
            riderCount: Int(info.riderCount) ?? 0,
            rideStatus: info.rideStatus,
            roomCount: Int(info.roomCount) ?? 0
        )

        if !discoveredRides.contains(where: { $0.id == ride.id }) {
            discoveredRides.append(ride)
        }
    }

    func browser(_ browser: MeshBrowser, didLose peerID: MCPeerID) {
        discoveredRides.removeAll { $0.peerID == peerID }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let meshVoiceStreamReceived = Notification.Name("meshVoiceStreamReceived")
    static let meshPeerConnected = Notification.Name("meshPeerConnected")
    static let meshPeerDisconnected = Notification.Name("meshPeerDisconnected")
}

// MARK: - Discovery Info Helper

struct MeshDiscoveryInfo {
    let rideId: String
    let rideName: String
    let leaderName: String
    let riderCount: String
    let rideStatus: String
    let roomCount: String
    let version: String

    var dictionary: [String: String] {
        [
            "rid": rideId,
            "rn": rideName,
            "ln": leaderName,
            "rc": riderCount,
            "rs": rideStatus,
            "rmc": roomCount,
            "v": version
        ]
    }

    static func from(_ dict: [String: String]?) -> MeshDiscoveryInfo? {
        guard let dict,
              let rideId = dict["rid"],
              let rideName = dict["rn"],
              let leaderName = dict["ln"],
              let riderCount = dict["rc"],
              let rideStatus = dict["rs"],
              let roomCount = dict["rmc"],
              let version = dict["v"]
        else { return nil }

        return MeshDiscoveryInfo(
            rideId: rideId,
            rideName: rideName,
            leaderName: leaderName,
            riderCount: riderCount,
            rideStatus: rideStatus,
            roomCount: roomCount,
            version: version
        )
    }
}
