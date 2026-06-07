import Foundation
import MultipeerConnectivity

// MARK: - Mesh Browser Delegate

protocol MeshBrowserDelegate: AnyObject {
    func browser(_ browser: MeshBrowser, didFind peerID: MCPeerID, with discoveryInfo: [String: String]?)
    func browser(_ browser: MeshBrowser, didLose peerID: MCPeerID)
}

// MARK: - Mesh Browser

final class MeshBrowser: NSObject, MCNearbyServiceBrowserDelegate {
    private let peerID: MCPeerID
    private let serviceType: String
    private var browser: MCNearbyServiceBrowser?

    weak var delegate: MeshBrowserDelegate?

    init(peerID: MCPeerID, serviceType: String) {
        self.peerID = peerID
        self.serviceType = serviceType
        super.init()
    }

    func start() {
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    func invite(_ peerID: MCPeerID, to session: MCSession) {
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    // MARK: - MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        delegate?.browser(self, didFind: peerID, with: info)
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        delegate?.browser(self, didLose: peerID)
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        print("🔗 Browser failed to start: \(error)")
    }
}
