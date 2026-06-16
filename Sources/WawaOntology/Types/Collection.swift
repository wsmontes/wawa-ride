import Foundation

/// An ordered collection of objects (ride album, photo set, etc.).
///
/// ActivityStreams `OrderedCollection` with Wawa extensions.
/// Each item is referenced by its object ID; the full objects
/// are resolved by the consumer.
///
/// Example: a ride album is a Collection of MediaObject references.
public struct WawaCollection: WawaObject, Equatable {
    // MARK: - WawaObject

    public static let wawaType = "wawa:Collection"
    public static let additionalTypes = ["OrderedCollection"]

    public let id: String
    public var attributedTo: String?
    public let published: Date
    public var updated: Date?
    public var proof: WawaProof?
    public var wawaExtensions: [String: WawaValue]

    // MARK: - Collection fields

    /// Collection name (e.g., "Sunday Ride Photos").
    public var name: String?

    /// Short description.
    public var summary: String?

    /// Total number of items in the collection.
    public var totalItems: Int

    /// Ordered list of object IDs.
    ///
    /// Each entry is an identifier (URN, DID, or URL) that
    /// can be resolved to the actual object.
    public var orderedItems: [String]

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
        totalItems: Int = 0,
        orderedItems: [String] = []
    ) {
        self.id = id
        self.attributedTo = attributedTo
        self.published = published
        self.updated = updated
        self.proof = proof
        self.wawaExtensions = wawaExtensions
        self.name = name
        self.summary = summary
        self.totalItems = totalItems
        self.orderedItems = orderedItems
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, summary, totalItems, orderedItems
        case attributedTo, published, updated, proof
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        totalItems = try container.decodeIfPresent(Int.self, forKey: .totalItems) ?? 0
        orderedItems = try container.decodeIfPresent([String].self, forKey: .orderedItems) ?? []
        attributedTo = try container.decodeIfPresent(String.self, forKey: .attributedTo)
        published = try container.decodeIfPresent(Date.self, forKey: .published) ?? Date()
        updated = try container.decodeIfPresent(Date.self, forKey: .updated)
        proof = try container.decodeIfPresent(WawaProof.self, forKey: .proof)
        wawaExtensions = try WawaCollection.decodeWawaExtensions(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(totalItems, forKey: .totalItems)
        if !orderedItems.isEmpty { try container.encode(orderedItems, forKey: .orderedItems) }
        try container.encodeIfPresent(attributedTo, forKey: .attributedTo)
        try container.encode(published, forKey: .published)
        try container.encodeIfPresent(updated, forKey: .updated)
        try container.encodeIfPresent(proof, forKey: .proof)
        try WawaCollection.encodeWawaExtensions(wawaExtensions, to: encoder)
    }
}
