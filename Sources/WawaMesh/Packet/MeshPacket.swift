import Foundation

/// Mesh packet type identifiers.
///
/// Inspired by BitChat's MessageType enum but tailored for ride tracking.
/// BitChat types: announce, message, noiseHandshake, noiseEncrypted, fragment, fileTransfer, leave, requestSync
/// Reference: https://github.com/permissionlesstech/bitchat/blob/main/localPackages/BitFoundation/Sources/BitFoundation/MessageType.swift
public enum PacketType: UInt8, Sendable {
    case announce       = 0x01  // Peer discovery (nickname, capabilities)
    case locationUpdate = 0x02  // GPS position (CompactLocation, 12 bytes)
    case routeShare     = 0x03  // Leader shares planned route with group
    case waypointSync   = 0x04  // Shared waypoints (gas stops, meeting points)
    case groupControl   = 0x05  // Join/leave/PIN validation
    case noiseHandshake = 0x10  // Phase 2: Noise_XX key exchange
    case noiseEncrypted = 0x11  // Phase 2: Encrypted payload
    case fragment       = 0x20  // Fragment of a larger packet (header 0xFE)
    case requestSync    = 0x30  // Gossip sync request (GCS filter)
}

/// Binary mesh packet — the core data unit transmitted over BLE and Nostr.
///
/// Wire format derived from BitChat's BinaryProtocol.swift (v2, 16-byte header):
/// https://github.com/permissionlesstech/bitchat/blob/main/localPackages/BitFoundation/Sources/BitFoundation/BinaryProtocol.swift
///
/// Header layout:
/// ```
/// [Version:1][Type:1][TTL:1][Timestamp:8][Flags:1][PayloadLen:4] = 16 bytes
/// ```
///
/// Variable fields (after header):
/// ```
/// [SenderID:8][RecipientID:8?][Route?][Payload:var][Signature:64?]
/// ```
///
/// Design decisions from BitChat:
/// - Big-endian byte order (network standard)
/// - TTL excluded from signature (changes during relay)
/// - Flags bitmap for optional fields (saves bytes when fields absent)
/// - 8-byte PeerID derived from first 8 bytes of SHA256(publicKey)
public struct MeshPacket: Sendable {
    public let version: UInt8
    public let type: PacketType
    public var ttl: UInt8
    public let timestamp: UInt64       // milliseconds since epoch
    public let senderID: Data          // 8 bytes (peer identity)
    public let recipientID: Data?      // 8 bytes, nil = broadcast to all
    public let payload: Data           // type-specific content
    public let signature: Data?        // 64 bytes Ed25519 (phase 2)
    public let route: [Data]?          // source routing hops, 8B each (phase 2)

    /// Deduplication key. Format matches BitChat: "{senderHex}-{timestamp}-{type}"
    /// Reference: BitChat's BLEReceivePipeline.swift messageID construction
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
