import Foundation

/// Location payload sent over the mesh network.
public struct LocationPayload: Codable, Sendable {
    public let lat: Double
    public let lon: Double
    public let heading: Double?
    public let speed: Double?
    public let accuracy: Double
    public let timestamp: TimeInterval

    public init(lat: Double, lon: Double, heading: Double?, speed: Double?, accuracy: Double, timestamp: TimeInterval) {
        self.lat = lat; self.lon = lon; self.heading = heading
        self.speed = speed; self.accuracy = accuracy; self.timestamp = timestamp
    }
}
