import Foundation
import MultipeerConnectivity

/// Persistent peer identity. Survives app restarts via NSKeyedArchiver ↔ UserDefaults.
struct PeerIdentity: Codable, Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let peerIDData: Data

    var mcPeerID: MCPeerID? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: peerIDData)
    }

    static func create(displayName: String) -> PeerIdentity {
        let mcPeerID = MCPeerID(displayName: displayName)
        let data = (try? NSKeyedArchiver.archivedData(withRootObject: mcPeerID, requiringSecureCoding: true)) ?? Data()
        return PeerIdentity(id: UUID(), displayName: displayName, peerIDData: data)
    }
}
