import Foundation

/// LRU deduplication cache for mesh packets.
///
/// Prevents processing the same packet multiple times in a flooding network.
/// Key format: "{senderID_hex}-{timestamp}-{type}" (matches BitChat's pattern).
///
/// Reference: BitChat's MessageDeduplicator (Utils/MessageDeduplicator.swift)
/// https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Utils/MessageDeduplicator.swift
///
/// BitChat parameters: capacity=1000, maxAge=300s (5 min).
/// Eviction strategy: when cache exceeds 50% capacity, purge all entries older than maxAge.
/// This amortizes the O(n) scan cost over many inserts.
///
/// Why not Bloom filter? BitChat uses GCS (Golomb-Coded Set) for gossip sync,
/// but for real-time dedup a simple hash map is faster and allows age-based eviction.
/// GCS is only needed for the "what do you have?" protocol (phase 2).
public final class MessageDeduplicator: @unchecked Sendable {
    private var cache: [String: Date] = [:]
    private let lock = NSLock()

    public init() {}

    /// Returns true if messageID hasn't been seen within maxAge.
    /// Thread-safe (NSLock). O(1) amortized.
    public func isNew(_ messageID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        // Amortized eviction: purge old entries when cache is half full
        if cache.count > MeshConfig.dedupMaxCount / 2 {
            cache = cache.filter { now.timeIntervalSince($0.value) < MeshConfig.dedupMaxAge }
        }
        if cache[messageID] != nil { return false }
        cache[messageID] = now
        return true
    }
}
