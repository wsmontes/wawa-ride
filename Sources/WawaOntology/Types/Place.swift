import Foundation

/// A geographic place with coordinates and a type.
///
/// Schema.org `Place` with Wawa extensions for place type
/// (meeting point, hazard, waypoint, parking, fuel stop, etc.).
///
/// Maps from the existing `Waypoint` (GRDB) and `CompactLocation` (BLE binary)
/// on the transport side.
public struct Place: WawaObject, Equatable {
    // MARK: - WawaObject

    public static let wawaType = "wawa:Place"
    public static let additionalTypes = ["Place"]

    public let id: String
    public var attributedTo: String?
    public let published: Date
    public var updated: Date?
    public var proof: WawaProof?
    public var wawaExtensions: [String: WawaValue]

    // MARK: - schema:Place fields

    /// Human-readable name (e.g., "Victoria Tim Hortons").
    public var name: String?

    /// Geographic coordinates.
    public var geo: GeoCoordinates

    /// Optional address or description.
    public var description: String?

    // MARK: - wawa:Place extensions

    /// Classification of this place.
    public var placeType: PlaceType

    // MARK: - Init

    public init(
        id: String,
        attributedTo: String? = nil,
        published: Date = Date(),
        updated: Date? = nil,
        proof: WawaProof? = nil,
        wawaExtensions: [String: WawaValue] = [:],
        name: String? = nil,
        geo: GeoCoordinates,
        description: String? = nil,
        placeType: PlaceType = .waypoint
    ) {
        self.id = id
        self.attributedTo = attributedTo
        self.published = published
        self.updated = updated
        self.proof = proof
        self.wawaExtensions = wawaExtensions
        self.name = name
        self.geo = geo
        self.description = description
        self.placeType = placeType
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, geo, description
        case attributedTo, published, updated, proof
        case placeType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        geo = try container.decode(GeoCoordinates.self, forKey: .geo)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        attributedTo = try container.decodeIfPresent(String.self, forKey: .attributedTo)
        published = try container.decodeIfPresent(Date.self, forKey: .published) ?? Date()
        updated = try container.decodeIfPresent(Date.self, forKey: .updated)
        proof = try container.decodeIfPresent(WawaProof.self, forKey: .proof)
        placeType = try container.decodeIfPresent(PlaceType.self, forKey: .placeType) ?? .waypoint
        wawaExtensions = try Place.decodeWawaExtensions(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(geo, forKey: .geo)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(attributedTo, forKey: .attributedTo)
        try container.encode(published, forKey: .published)
        try container.encodeIfPresent(updated, forKey: .updated)
        try container.encodeIfPresent(proof, forKey: .proof)
        try container.encode(placeType, forKey: .placeType)
        try Place.encodeWawaExtensions(wawaExtensions, to: encoder)
    }
}

// MARK: - GeoCoordinates

/// Geographic coordinates per Schema.org.
public struct GeoCoordinates: Codable, Sendable, Equatable {
    /// Schema.org type discriminator.
    public var type: String = "GeoCoordinates"

    /// Latitude in decimal degrees.
    public var latitude: Double

    /// Longitude in decimal degrees.
    public var longitude: Double

    /// Elevation in meters above sea level (optional).
    public var elevation: Double?

    public init(
        latitude: Double,
        longitude: Double,
        elevation: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }
}

// MARK: - PlaceType

public enum PlaceType: String, Codable, Sendable, Equatable {
    /// Starting meeting point for a ride.
    case meetingPoint
    /// Road hazard (pothole, debris, animal, accident, etc.).
    case hazard
    /// Route waypoint / via point.
    case waypoint
    /// Parking lot or parking area.
    case parking
    /// Fuel station.
    case fuel
    /// Photo spot / scenic viewpoint.
    case photo
    /// Rest stop / break point.
    case restStop
    /// Scenic viewpoint.
    case scenic
}
