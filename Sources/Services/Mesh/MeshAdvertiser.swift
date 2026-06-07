import Foundation
import MultipeerConnectivity

// MARK: - Mesh Advertiser Delegate

protocol MeshAdvertiserDelegate: AnyObject {
    func advertiser(_ advertiser: MeshAdvertiser, didReceiveInvitationFrom peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void)
}

// MARK: - Mesh Advertiser

final class MeshAdvertiser: NSObject, MCNearbyServiceAdvertiserDelegate {
    private let peerID: MCPeerID
    private let serviceType: String
    private var advertiser: MCNearbyServiceAdvertiser?

    weak var delegate: MeshAdvertiserDelegate?

    init(peerID: MCPeerID, serviceType: String) {
        self.peerID = peerID
        self.serviceType = serviceType
        super.init()
    }

    func start(with discoveryInfo: MeshDiscoveryInfo) {
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: discoveryInfo.dictionary,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Delegate to MeshService which will provide the session and accept
        delegate?.advertiser(self, didReceiveInvitationFrom: peerID, invitationHandler: invitationHandler)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("🔗 Advertiser failed to start: \(error)")
    }
}
