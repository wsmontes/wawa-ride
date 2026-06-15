import Foundation

/// Fragment/reassembly for packets exceeding BLE MTU.
/// Header: [0xFE][totalChunks:1][chunkIndex:1][transferID:2]
public enum FragmentCodec {
    private static let headerSize = 5
    private static let magic: UInt8 = 0xFE

    public static func isFragment(_ data: Data) -> Bool {
        data.count >= headerSize && data[0] == magic
    }

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

/// Reassembly buffer — stores partial fragment transfers.
public final class FragmentAssemblyBuffer: @unchecked Sendable {
    private struct Transfer { var chunks: [Int: Data]; let total: Int; let created: Date }
    private var transfers: [String: Transfer] = [:]
    private let lock = NSLock()

    public init() {}

    /// Returns assembled data when all fragments received, nil otherwise.
    public func addFragment(_ data: Data, from peer: UUID) -> Data? {
        guard data.count >= 5, data[0] == 0xFE else { return nil }
        let total = Int(data[1])
        let index = Int(data[2])
        let tid = data[3..<5].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let key = "\(peer)-\(tid)"
        let payload = data.subdata(in: 5..<data.count)

        lock.lock()
        defer { lock.unlock() }

        // Evict stale
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
