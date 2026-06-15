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

/// Announce payload — broadcast on join and periodically (~30s).
/// Contains identity, group membership, and visibility preference.
public struct AnnouncePayload: Codable, Sendable {
    public let nickname: String
    public let groupID: String
    public let visibility: Visibility

    public init(nickname: String, groupID: String, visibility: Visibility = .public) {
        self.nickname = nickname; self.groupID = groupID; self.visibility = visibility
    }
}

/// Rider visibility level — controls who sees you on their map.
///
/// This enables an open presence network:
/// - .public: any WawaMesh rider nearby sees you (green dot, position only)
/// - .groupOnly: only your group members see you (orange dot, full trail)
/// - .hidden: invisible to everyone outside your group AND not relayed
public enum Visibility: String, Codable, Sendable {
    case `public`    // visible to all WawaMesh riders nearby
    case groupOnly   // visible only to same groupID
    case hidden      // not broadcast outside group, not relayed for others
}
