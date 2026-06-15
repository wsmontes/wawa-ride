import Foundation

/// Protocol constants derived from BitChat's TransportConfig.
public enum MeshConfig {
    public static let defaultTTL: UInt8 = 7
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
}
