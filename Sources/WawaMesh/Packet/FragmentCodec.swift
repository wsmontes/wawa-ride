import Foundation

/// Fragment/reassembly for packets exceeding BLE MTU (469 bytes).
///
/// Reference: BitChat's BLEOutboundFragmentPlanner + BLEFragmentAssemblyBuffer
/// https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/BLE/BLEOutboundFragmentPlanner.swift
/// https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/BLE/BLEFragmentAssemblyBuffer.swift
///
/// Fragment header format (5 bytes):
/// ```
/// [0xFE magic][totalChunks:1][chunkIndex:1][transferID:2]
/// ```
///
/// Why 0xFE? It's an invalid first byte for both our packet header (version=2)
/// and JSON (starts with '{'), making fragment detection unambiguous.
///
/// BitChat spaces fragments at 30ms intervals to avoid overflowing the
/// BLE peripheral's notification buffer. See MeshConfig.bleFragmentSpacingMs.
public enum FragmentCodec {
    private static let headerSize = 5
    private static let magic: UInt8 = 0xFE

    /// Check if data is a fragment (starts with magic byte 0xFE).
    public static func isFragment(_ data: Data) -> Bool {
        data.count >= headerSize && data[0] == magic
    }

    /// Split data into fragments that fit within BLE MTU.
    /// Each fragment carries a 5-byte header + payload chunk.
    ///
    /// - Parameters:
    ///   - data: The full encoded packet to fragment
    ///   - maxSize: Max bytes per fragment (default: MeshConfig.bleFragmentSize = 469)
    /// - Returns: Array of fragment Data to send sequentially with 30ms spacing
    public static func fragment(_ data: Data, maxSize: Int = MeshConfig.bleFragmentSize) -> [Data] {
        let payloadPerChunk = maxSize - headerSize
        let total = (data.count + payloadPerChunk - 1) / payloadPerChunk
        let transferID = UInt16.random(in: 0...UInt16.max)
        return (0..<total).map { i in
            var chunk = Data(capacity: maxSize)
            chunk.append(magic)
            chunk.append(UInt8(total))
            chunk.append(UInt8(i))
            withUnsafeBytes(of: transferID.bigEndian) { chunk.append(contentsOf: $0) }
            let start = i * payloadPerChunk
            let end = min(start + payloadPerChunk, data.count)
            chunk.append(data[start..<end])
            return chunk
        }
    }
}

/// Reassembly buffer — stores partial fragment transfers until complete.
///
/// Reference: BitChat's BLEFragmentAssemblyBuffer (max 128 concurrent assemblies)
/// https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/BLE/BLEFragmentAssemblyBuffer.swift
///
/// Key design: keyed by "{peerUUID}-{transferID}" to support multiple
/// concurrent transfers from different peers without collision.
public final class FragmentAssemblyBuffer: @unchecked Sendable {
    private struct Transfer { var chunks: [Int: Data]; let total: Int; let created: Date }
    private var transfers: [String: Transfer] = [:]
    private let lock = NSLock()

    public init() {}

    /// Add a fragment. Returns assembled full data when all chunks received, nil otherwise.
    ///
    /// Thread-safe via NSLock. Evicts stale transfers (>30s) when buffer is full.
    public func addFragment(_ data: Data, from peer: UUID) -> Data? {
        guard data.count >= 5, data[0] == 0xFE else { return nil }
        let total = Int(data[1])
        let index = Int(data[2])
        let tid = data[3..<5].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let key = "\(peer)-\(tid)"
        let payload = data.subdata(in: 5..<data.count)

        lock.lock()
        defer { lock.unlock() }

        // Evict stale assemblies to prevent memory exhaustion
        if transfers.count >= MeshConfig.bleMaxInFlightAssemblies {
            let now = Date()
            transfers = transfers.filter { now.timeIntervalSince($0.value.created) < 30 }
        }
        if transfers[key] == nil {
            transfers[key] = Transfer(chunks: [:], total: total, created: Date())
        }
        transfers[key]?.chunks[index] = payload
        guard let t = transfers[key], t.chunks.count == total else { return nil }
        transfers.removeValue(forKey: key)
        var assembled = Data()
        for i in 0..<total { if let c = t.chunks[i] { assembled.append(c) } }
        return assembled
    }
}
