import Foundation

/// LRU deduplication cache. Key format: "{senderID}-{timestamp}-{type}"
public final class MessageDeduplicator: @unchecked Sendable {
    private var cache: [String: Date] = [:]
    private let lock = NSLock()

    public init() {}

    /// Returns true if messageID hasn't been seen within maxAge.
    public func isNew(_ messageID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if cache.count > MeshConfig.dedupMaxCount / 2 {
            cache = cache.filter { now.timeIntervalSince($0.value) < MeshConfig.dedupMaxAge }
        }
        if cache[messageID] != nil { return false }
        cache[messageID] = now
        return true
    }
}
