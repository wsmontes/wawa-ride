import Foundation

/// A motorcycle ride route — an ordered sequence of geographic points.
///
/// Maps from:
/// - `RouteCorridor` (Turf LineString) — the map-rendered shape
/// - `MatchedRoute` (Valhalla Meili) — map-matched GPS trace
/// - GPX file import — external route files
///
/// The route is stored as JSON-LD with ordered `waypoints`.
/// For rendering, waypoints are projected to Turf `LineString` coordinates.
public struct Route: WawaObject, Equatable {
    // MARK: - WawaObject

    public static let wawaType = "wawa:RideRoute"
    public static let additionalTypes: [String] = []

    public let id: String
    public var attributedTo: String?
    public let published: Date
    public var updated: Date?
    public var proof: WawaProof?
    public var wawaExtensions: [String: WawaValue]

    // MARK: - Route fields

    /// Route name (e.g., "Victoria to Sooke via Highway 14").
    public var name: String?

    /// Ordered path as geographic coordinates.
    public var waypoints: [GeoCoordinates]

    /// Total distance in meters.
    public var distanceMeters: Double?

    /// Estimated duration in seconds.
    public var durationSeconds: Double?

    /// Source of the route data.
    public var source: String?

    // MARK: - Init

    public init(
        id: String,
        attributedTo: String? = nil,
        published: Date = Date(),
        updated: Date? = nil,
        proof: WawaProof? = nil,
        wawaExtensions: [String: WawaValue] = [:],
        name: String? = nil,
        waypoints: [GeoCoordinates] = [],
        distanceMeters: Double? = nil,
        durationSeconds: Double? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.attributedTo = attributedTo
        self.published = published
        self.updated = updated
        self.proof = proof
        self.wawaExtensions = wawaExtensions
        self.name = name
        self.waypoints = waypoints
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.source = source
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, waypoints, distanceMeters, durationSeconds, source
        case attributedTo, published, updated, proof
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        waypoints = try container.decodeIfPresent([GeoCoordinates].self, forKey: .waypoints) ?? []
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        attributedTo = try container.decodeIfPresent(String.self, forKey: .attributedTo)
        published = try container.decodeIfPresent(Date.self, forKey: .published) ?? Date()
        updated = try container.decodeIfPresent(Date.self, forKey: .updated)
        proof = try container.decodeIfPresent(WawaProof.self, forKey: .proof)
        wawaExtensions = try Route.decodeWawaExtensions(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        if !waypoints.isEmpty { try container.encode(waypoints, forKey: .waypoints) }
        try container.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(attributedTo, forKey: .attributedTo)
        try container.encode(published, forKey: .published)
        try container.encodeIfPresent(updated, forKey: .updated)
        try container.encodeIfPresent(proof, forKey: .proof)
        try Route.encodeWawaExtensions(wawaExtensions, to: encoder)
    }
}
