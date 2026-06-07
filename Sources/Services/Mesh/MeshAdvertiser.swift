import Foundation
import MultipeerConnectivity

// MARK: - Mesh Advertiser Delegate

protocol MeshAdvertiserDelegate: AnyObject {
    func advertiser(_ advertiser: MeshAdvertiser, didReceiveInvitationFrom peerID: MCPeerID)
}

// MARK: - Mesh Advertiser

final class MeshAdvertiser: NSObject, MCNearbyServiceAdvertiserDelegate {
    private let peerID: MCPeerID
    private let serviceType: String
    private var advertiser: MCNearbyServiceAdvertiser?

    weak var delegate: MeshAdvertiserDelegate?

    // Store pending invitations for context
    private var invitationContexts: [String: Data] = [:]

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
        invitationContexts.removeAll()
    }

    func invitationContext(from peerID: MCPeerID) -> Data? {
        invitationContexts[peerID.displayName]
    }

    func acceptInvitation(from peerID: MCPeerID, into session: MCSession) {
        // Invitation is auto-accepted in the delegate callback.
        // This method is a no-op kept for API consistency.
        // The invitation handler is called directly in
        // advertiser(_:didReceiveInvitationFromPeer:withContext:invitationHandler:)
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept in MVP
        invitationContexts[peerID.displayName] = context

        // Get the current session from MeshService
        let session = MeshService.shared.session
        invitationHandler(true, session)

        delegate?.advertiser(self, didReceiveInvitationFrom: peerID)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("🔗 Advertiser failed to start: \(error)")
    }
}
