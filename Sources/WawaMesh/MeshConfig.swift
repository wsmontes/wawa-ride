import Foundation

/// Protocol constants for the WawaMesh network.
///
/// These values are derived from BitChat's TransportConfig.swift:
/// https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/TransportConfig.swift
///
/// TTL, fragment sizes, and dedup parameters were validated in BitChat's
/// production mesh network (~26k stars, 900+ commits as of Jun 2026).
public enum MeshConfig {
    /// Maximum hop count for flood relay. Reduced from BitChat's default (7) to 5
    /// for motorcycle groups of 5-7 riders where range is limited.
    /// Reference: BitChat uses `messageTTLDefault = 7`
    public static let defaultTTL: UInt8 = 5

    /// Max BLE characteristic write payload (bytes).
    /// Derived from BitChat's `bleDefaultFragmentSize = 469`.
    /// Apple's CoreBluetooth allows up to 512 bytes per write, minus ATT overhead.
    /// Reference: https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:)
    public static let bleFragmentSize = 469

    /// Delay between fragment transmissions (ms).
    /// Prevents BLE peripheral buffer overflow on rapid writes.
    /// Reference: BitChat's `bleFragmentSpacingMs = 30`
    public static let bleFragmentSpacingMs = 30

    /// Max simultaneous BLE central connections.
    /// Apple recommends ≤7 for stable performance. BitChat uses 6.
    /// Reference: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/
    public static let bleMaxCentralLinks = 6

    /// Timeout for BLE connection attempts.
    /// Reference: BitChat's `bleConnectTimeoutSeconds = 8.0`
    public static let bleConnectTimeout: TimeInterval = 8.0

    /// Interval for BLE housekeeping (stale peer cleanup, reconnection attempts).
    /// Reference: BitChat's `bleMaintenanceInterval = 5.0`
    public static let bleMaintenanceInterval: TimeInterval = 5.0

    /// Max concurrent fragment reassembly buffers.
    /// Prevents memory exhaustion from incomplete transfers.
    /// Reference: BitChat's `bleMaxInFlightAssemblies = 128`
    public static let bleMaxInFlightAssemblies = 128

    /// Deduplication cache expiry. Messages older than this are forgotten.
    /// Reference: BitChat's `messageDedupMaxAgeSeconds = 300`
    public static let dedupMaxAge: TimeInterval = 300

    /// Deduplication cache capacity. Eviction triggered at 50% to amortize cost.
    /// Reference: BitChat's `messageDedupMaxCount = 1000`
    public static let dedupMaxCount = 1000

    /// Gossip sync interval (seconds). Not used in MVP.
    /// Reference: BitChat's `syncInterval` pattern in GossipSyncManager.swift
    public static let syncInterval: TimeInterval = 15.0

    /// GPS broadcast rate during active ride (Hz).
    /// OwnTracks pattern: only broadcast when OS detects movement.
    /// Reference: https://github.com/owntracks/ios — LocationManager approach
    public static let locationBroadcastHz: Double = 1.0

    /// GPS broadcast rate when idle/stationary (Hz).
    public static let locationIdleHz: Double = 0.1

    /// Mark rider as "stale" after this many seconds without update.
    /// Visual feedback: rider icon turns gray at 50% opacity.
    public static let riderStaleTimeout: TimeInterval = 15

    /// Remove rider from map entirely after this timeout.
    /// Prevents ghost markers from disconnected peers.
    public static let riderRemoveTimeout: TimeInterval = 120
}
