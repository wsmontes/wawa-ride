import Foundation

/// Protocol constants derived from BitChat's TransportConfig.
public enum MeshConfig {
    public static let defaultTTL: UInt8 = 5
    public static let bleFragmentSize = 469
    public static let bleFragmentSpacingMs = 30
    public static let bleMaxCentralLinks = 6
    public static let bleConnectTimeout: TimeInterval = 8.0
    public static let bleMaintenanceInterval: TimeInterval = 5.0
    public static let bleMaxInFlightAssemblies = 128
    public static let dedupMaxAge: TimeInterval = 300
    public static let dedupMaxCount = 1000
    public static let syncInterval: TimeInterval = 15.0
    public static let locationBroadcastHz: Double = 1.0
    public static let locationIdleHz: Double = 0.1
    public static let riderStaleTimeout: TimeInterval = 15  // mark stale after 15s no update
    public static let riderRemoveTimeout: TimeInterval = 120 // remove after 2 min
}
