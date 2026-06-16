import Foundation

/// WawaMesh-specific constants (non-protocol, app-level).
///
/// Protocol-level constants (TTL, fragment sizes, dedup params)
/// come from BitChat's production-tuned values. This file holds
/// only WawaRide-specific tuning: GPS broadcast rates, rider
/// timeout thresholds, etc.
public enum MeshConstants {
    /// GPS broadcast rate during active ride (Hz).
    /// OwnTracks pattern: only broadcast when OS detects movement.
    public static let locationBroadcastHz: Double = 1.0

    /// GPS broadcast rate when idle/stationary (Hz).
    public static let locationIdleHz: Double = 0.1

    /// Mark rider as "stale" after this many seconds without update.
    /// Visual feedback: rider icon turns gray at 50% opacity.
    public static let riderStaleTimeout: TimeInterval = 15

    /// Remove rider from map entirely after this timeout.
    public static let riderRemoveTimeout: TimeInterval = 120
}
