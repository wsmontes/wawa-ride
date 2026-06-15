import Foundation

/// Binary encode/decode for MeshPacket.
///
/// Wire format (v2, 16-byte header + variable):
/// ```
/// [Version:1][Type:1][TTL:1][Timestamp:8][Flags:1][PayloadLen:4][SenderID:8][...variable...]
/// ```
///
/// Reference implementation: BitChat's BinaryProtocol.swift
/// https://github.com/permissionlesstech/bitchat/blob/main/localPackages/BitFoundation/Sources/BitFoundation/BinaryProtocol.swift
///
/// Key design from BitChat:
/// - All multi-byte integers are big-endian (network byte order)
/// - Flags byte uses bitmask for optional fields (saves space)
/// - PayloadLen is 4 bytes (supports up to 4GB, future-proof)
/// - SenderID always present (8 bytes, mandatory)
/// - RecipientID only present if unicast (flag bit 0)
public enum BinaryCodec {

    // MARK: - Flags (from BitChat's BinaryProtocol)
    // bit 0 (0x01) = hasRecipient (unicast message)
    // bit 1 (0x02) = hasSignature (Ed25519, 64 bytes)
    // bit 2 (0x04) = isCompressed (zlib, not used in MVP)
    // bit 3 (0x08) = hasRoute (source routing, phase 2)
    // bit 4 (0x10) = isRSR (request-sync-response, phase 2)

    public static func encode(_ packet: MeshPacket) -> Data {
        var d = Data(capacity: 32 + packet.payload.count)
        d.append(packet.version)
        d.append(packet.type.rawValue)
        d.append(packet.ttl)
        appendBigEndian(&d, packet.timestamp)

        var flags: UInt8 = 0
        if packet.recipientID != nil { flags |= 0x01 }
        if packet.signature != nil  { flags |= 0x02 }
        if packet.route != nil      { flags |= 0x08 }
        d.append(flags)

        appendBigEndian(&d, UInt32(packet.payload.count))
        d.append(packet.senderID)
        if let r = packet.recipientID { d.append(r) }
        if let route = packet.route {
            d.append(UInt8(route.count))
            for hop in route { d.append(hop) }
        }
        d.append(packet.payload)
        if let sig = packet.signature { d.append(sig) }
        return d
    }

    public static func decode(_ data: Data) -> MeshPacket? {
        guard data.count >= 16 else { return nil }
        var o = 0
        let version = data[o]; o += 1
        guard let type = PacketType(rawValue: data[o]) else { return nil }; o += 1
        let ttl = data[o]; o += 1
        let timestamp: UInt64 = readBigEndian(data, at: &o)
        let flags = data[o]; o += 1
        let payloadLen = Int(readBigEndian(data, at: &o) as UInt32)
        guard data.count >= o + 8 + payloadLen else { return nil }
        let senderID = data[o..<o+8]; o += 8
        let recipientID: Data? = (flags & 0x01 != 0) ? { let d = data[o..<o+8]; o += 8; return Data(d) }() : nil
        let route: [Data]? = (flags & 0x08 != 0) ? {
            let c = Int(data[o]); o += 1
            return (0..<c).map { _ in let h = Data(data[o..<o+8]); o += 8; return h }
        }() : nil
        guard data.count >= o + payloadLen else { return nil }
        let payload = Data(data[o..<o+payloadLen]); o += payloadLen
        let signature: Data? = (flags & 0x02 != 0 && data.count >= o + 64) ? Data(data[o..<o+64]) : nil

        return MeshPacket(version: version, type: type, ttl: ttl, timestamp: timestamp,
                          senderID: Data(senderID), recipientID: recipientID,
                          payload: payload, signature: signature, route: route)
    }

    // MARK: - Helpers

    private static func appendBigEndian<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    private static func readBigEndian<T: FixedWidthInteger>(_ data: Data, at offset: inout Int) -> T {
        let size = MemoryLayout<T>.size
        let value = data[offset..<offset+size].withUnsafeBytes { $0.load(as: T.self) }.bigEndian
        offset += size
        return value
    }
}
