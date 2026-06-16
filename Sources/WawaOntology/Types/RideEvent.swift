import Foundation

/// A motorcycle ride event.
///
/// Schema.org `Event` with Wawa extensions for ride type, visibility,
/// mesh group coordination, and participant tracking.
///
/// ## Lifecycle
///
/// ```
/// proposed → active → completed
///                  → cancelled
/// ```
///
/// ## Transport projection
///
/// In BLE mesh: the `meshGroupId`, `startDate`, and leader location
/// are projected into `MeshPacket` payloads. The full `RideEvent` JSON-LD
/// is stored locally and shared via MultipeerKit/Nostr when available.
public struct RideEvent: WawaObject, Equatable {
    // MARK: - WawaObject

    public static let wawaType = "wawa:RideEvent"
    public static let additionalTypes = ["Event"]

    public let id: String
    public var attributedTo: String?
    public let published: Date
    public var updated: Date?
    public var proof: WawaProof?
    public var wawaExtensions: [String: WawaValue]

    // MARK: - schema:Event fields

    /// Ride name (e.g., "Sunday Morning Ride").
    public var name: String?

    /// Short description or notes.
    public var summary: String?

    /// Ride start time.
    public var startDate: Date

    /// Ride end time (estimated or actual).
    public var endDate: Date?

    /// Meeting point or start location.
    public var location: Place?

    // MARK: - wawa:RideEvent extensions

    /// Type of ride.
    public var rideType: RideType

    /// Who can discover/join this ride.
    public var visibility: Visibility

    /// BLE mesh group identifier for local peer discovery.
    ///
    /// Riders with the same `meshGroupId` discover each other via
    /// BLE announcements and form a mesh.
    public var meshGroupId: String?

    /// Whether this ride works fully offline.
    public var offlineCapable: Bool

    /// DID references to participants.
    public var participants: [String]

    /// Current ride status.
    public var status: RideStatus

    // MARK: - Init

    public init(
        id: String,
        attributedTo: String? = nil,
        published: Date = Date(),
        updated: Date? = nil,
        proof: WawaProof? = nil,
        wawaExtensions: [String: WawaValue] = [:],
        name: String? = nil,
        summary: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        location: Place? = nil,
        rideType: RideType = .groupRide,
        visibility: Visibility = .groupOnly,
        meshGroupId: String? = nil,
        offlineCapable: Bool = true,
        participants: [String] = [],
        status: RideStatus = .proposed
    ) {
        self.id = id
        self.attributedTo = attributedTo
        self.published = published
        self.updated = updated
        self.proof = proof
        self.wawaExtensions = wawaExtensions
        self.name = name
        self.summary = summary
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.rideType = rideType
        self.visibility = visibility
        self.meshGroupId = meshGroupId
        self.offlineCapable = offlineCapable
        self.participants = participants
        self.status = status
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, summary, startDate, endDate, location
        case attributedTo, published, updated, proof
        case rideType, visibility, meshGroupId, offlineCapable
        case participants, status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        location = try container.decodeIfPresent(Place.self, forKey: .location)
        attributedTo = try container.decodeIfPresent(String.self, forKey: .attributedTo)
        published = try container.decodeIfPresent(Date.self, forKey: .published) ?? Date()
        updated = try container.decodeIfPresent(Date.self, forKey: .updated)
        proof = try container.decodeIfPresent(WawaProof.self, forKey: .proof)
        rideType = try container.decodeIfPresent(RideType.self, forKey: .rideType) ?? .groupRide
        visibility = try container.decodeIfPresent(Visibility.self, forKey: .visibility) ?? .groupOnly
        meshGroupId = try container.decodeIfPresent(String.self, forKey: .meshGroupId)
        offlineCapable = try container.decodeIfPresent(Bool.self, forKey: .offlineCapable) ?? true
        participants = try container.decodeIfPresent([String].self, forKey: .participants) ?? []
        status = try container.decodeIfPresent(RideStatus.self, forKey: .status) ?? .proposed
        wawaExtensions = try RideEvent.decodeWawaExtensions(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(attributedTo, forKey: .attributedTo)
        try container.encode(published, forKey: .published)
        try container.encodeIfPresent(updated, forKey: .updated)
        try container.encodeIfPresent(proof, forKey: .proof)
        try container.encode(rideType, forKey: .rideType)
        try container.encode(visibility, forKey: .visibility)
        try container.encodeIfPresent(meshGroupId, forKey: .meshGroupId)
        try container.encode(offlineCapable, forKey: .offlineCapable)
        if !participants.isEmpty { try container.encode(participants, forKey: .participants) }
        try container.encode(status, forKey: .status)
        try RideEvent.encodeWawaExtensions(wawaExtensions, to: encoder)
    }
}

// MARK: - Supporting enums

public enum RideType: String, Codable, Sendable, Equatable {
    /// Solo ride — no mesh, no group.
    case solo
    /// Group ride with mesh coordination.
    case groupRide
    /// Relay ride — riders relay messages for others.
    case relay
}

public enum RideStatus: String, Codable, Sendable, Equatable {
    /// Ride is proposed but not yet started.
    case proposed
    /// Ride is currently active.
    case active
    /// Ride completed normally.
    case completed
    /// Ride was cancelled.
    case cancelled
}

public enum Visibility: String, Codable, Sendable, Equatable {
    /// Visible to anyone (Nostr relay, public mesh).
    case `public`
    /// Visible only to group/club members.
    case groupOnly
    /// Visible only to invited participants.
    case `private`
}
