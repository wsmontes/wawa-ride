import Foundation
import MultipeerConnectivity
import os.log
#if canImport(UIKit)
import UIKit
#endif

// MCPeerID is thread-safe per Apple docs but not marked Sendable.
extension MCPeerID: @retroactive @unchecked Sendable {}

/// Handles Bluetooth/WiFi peer discovery, pairing persistence, and WebRTC signaling relay.
/// After initial pairing, WebRTC takes over for internet-routable communication.
final class MultipeerService: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published state

    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var nearbyPeers: [MCPeerID] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var pairingError: String?

    // MARK: - Properties

    private let serviceType = "wawaride-pair"
    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// Called when WebRTC signaling data (SDP / ICE) arrives over MC.
    var onSignalingData: ((Data, MCPeerID) -> Void)?

    private let log = Logger(subsystem: "com.wawaride", category: "Multipeer")

    // MARK: - Init

    override init() {
        let defaults = UserDefaults.standard
        #if os(iOS)
        let displayName = UIDevice.current.name
        #else
        let displayName = ProcessInfo.processInfo.hostName
        #endif
        let key = "wawa_persistent_peerID"

        if let savedData = defaults.data(forKey: key),
           let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: savedData) {
            myPeerID = saved
            log.info("Loaded persistent peerID: \(saved.displayName)")
        } else {
            myPeerID = MCPeerID(displayName: displayName)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: myPeerID, requiringSecureCoding: true) {
                defaults.set(data, forKey: key)
            }
            log.info("Created new persistent peerID: \(displayName)")
        }

        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        super.init()
        session.delegate = self
    }

    // MARK: - Public API

    func startPairing() {
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["app": "wawaride", "v": "0.1"],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
        log.info("Started advertising for pairing")
    }

    func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        log.info("Started browsing for peers")
    }

    func stopPairing() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false

        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
    }

    func invite(peer: MCPeerID) {
        guard let browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
        log.info("Invited peer: \(peer.displayName)")
    }

    /// Send WebRTC signaling data to one peer via MultipeerConnectivity.
    func sendSignaling(_ data: Data, to peer: MCPeerID) {
        guard session.connectedPeers.contains(peer) else {
            log.error("Cannot send signaling — peer not connected: \(peer.displayName)")
            return
        }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            log.error("Failed to send signaling: \(error.localizedDescription)")
        }
    }

    /// Broadcast to all connected peers.
    func broadcast(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            log.error("Broadcast failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeers.append(peerID)
                self.nearbyPeers.removeAll { $0 == peerID }
                self.log.info("Peer connected: \(peerID.displayName)")
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.log.info("Peer disconnected: \(peerID.displayName)")
            case .connecting:
                self.log.info("Peer connecting: \(peerID.displayName)")
            @unknown default: break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        onSignalingData?(data, peerID)
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        log.info("Received invitation from: \(peerID.displayName)")
        // Auto-accept all invitations for MVP.
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        DispatchQueue.main.async {
            guard !self.nearbyPeers.contains(peerID),
                  !self.connectedPeers.contains(peerID)
            else { return }
            self.nearbyPeers.append(peerID)
            self.log.info("Found nearby peer: \(peerID.displayName)")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.nearbyPeers.removeAll { $0 == peerID }
            self.log.info("Lost peer: \(peerID.displayName)")
        }
    }
}
