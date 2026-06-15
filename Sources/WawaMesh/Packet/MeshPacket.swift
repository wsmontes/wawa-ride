import Foundation

/// Mesh packet type identifiers.
public enum PacketType: UInt8, Sendable {
    case announce       = 0x01
    case locationUpdate = 0x02
    case routeShare     = 0x03
    case waypointSync   = 0x04
    case groupControl   = 0x05
    case noiseHandshake = 0x10
    case noiseEncrypted = 0x11
    case fragment       = 0x20
    case requestSync    = 0x30
}

/// Binary mesh packet — the core data unit transmitted over BLE and Nostr.
/// Wire format derived from BitChat's BinaryProtocol (v2, 16-byte header).
public struct MeshPacket: Sendable {
    public let version: UInt8
    public let type: PacketType
    public var ttl: UInt8
    public let timestamp: UInt64
    public let senderID: Data      // 8 bytes
    public let recipientID: Data?  // 8 bytes, nil = broadcast
    public let payload: Data
    public let signature: Data?    // 64 bytes
    public let route: [Data]?      // source routing hops (8B each)

    public var messageID: String {
        "\(senderID.hex)-\(timestamp)-\(type.rawValue)"
    }

    public init(version: UInt8 = 2, type: PacketType, ttl: UInt8 = MeshConfig.defaultTTL,
                timestamp: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
                senderID: Data, recipientID: Data? = nil,
                payload: Data, signature: Data? = nil, route: [Data]? = nil) {
        self.version = version
        self.type = type
        self.ttl = ttl
        self.timestamp = timestamp
        self.senderID = senderID
        self.recipientID = recipientID
        self.payload = payload
        self.signature = signature
        self.route = route
    }
}
