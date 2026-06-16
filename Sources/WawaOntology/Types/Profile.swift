import Foundation

/// A rider or peer profile.
///
/// Schema.org `Person` with Wawa extensions for mesh identity
/// and club affiliations. In Phase A, the `id` is a peer URN
/// (`urn:wawa:peer:<hex>`). In Phase B, it becomes a `did:key`.
public struct Profile: WawaObject, Equatable {
    // MARK: - WawaObject

    public static let wawaType = "wawa:Profile"
    public static let additionalTypes = ["Person"]

    public let id: String
    public var attributedTo: String?
    public let published: Date
    public var updated: Date?
    public var proof: WawaProof?
    public var wawaExtensions: [String: WawaValue]

    // MARK: - schema:Person fields

    /// Display name / nickname.
    public var name: String?

    /// First name (optional, for formal contexts).
    public var givenName: String?

    /// Last name (optional).
    public var familyName: String?

    /// Avatar image reference.
    public var image: MediaObject?

    // MARK: - wawa:Profile extensions

    /// Hex-encoded 8-byte mesh PeerID.
    ///
    /// Used for BLE mesh discovery and routing. Derived from
    /// the device's random identifier stored in UserDefaults.
    public var peerID: String?

    /// Ed25519 public key, multibase-encoded (Phase B).
    ///
    /// This is the cryptographic identity that backs a `did:key`.
    public var publicKey: String?

    /// DID references to club memberships.
    ///
    /// Each entry is a DID pointing to an Organization that
    /// has issued a ClubMembershipCredential to this profile.
    public var clubs: [String]

    // MARK: - Init

    public init(
        id: String,
        attributedTo: String? = nil,
        published: Date = Date(),
        updated: Date? = nil,
        proof: WawaProof? = nil,
        wawaExtensions: [String: WawaValue] = [:],
        name: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil,
        image: MediaObject? = nil,
        peerID: String? = nil,
        publicKey: String? = nil,
        clubs: [String] = []
    ) {
        self.id = id
        self.attributedTo = attributedTo ?? id  // self-created by default
        self.published = published
        self.updated = updated
        self.proof = proof
        self.wawaExtensions = wawaExtensions
        self.name = name
        self.givenName = givenName
        self.familyName = familyName
        self.image = image
        self.peerID = peerID
        self.publicKey = publicKey
        self.clubs = clubs
    }

    // MARK: - Codable (manual for wawaExtensions)

    enum CodingKeys: String, CodingKey {
        case id, name, givenName, familyName, image
        case attributedTo, published, updated, proof
        case peerID, publicKey, clubs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        givenName = try container.decodeIfPresent(String.self, forKey: .givenName)
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName)
        image = try container.decodeIfPresent(MediaObject.self, forKey: .image)
        attributedTo = try container.decodeIfPresent(String.self, forKey: .attributedTo)
        published = try container.decodeIfPresent(Date.self, forKey: .published) ?? Date()
        updated = try container.decodeIfPresent(Date.self, forKey: .updated)
        proof = try container.decodeIfPresent(WawaProof.self, forKey: .proof)
        peerID = try container.decodeIfPresent(String.self, forKey: .peerID)
        publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)
        clubs = try container.decodeIfPresent([String].self, forKey: .clubs) ?? []

        // Collect unknown keys into wawaExtensions
        wawaExtensions = try Profile.decodeWawaExtensions(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(givenName, forKey: .givenName)
        try container.encodeIfPresent(familyName, forKey: .familyName)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(attributedTo, forKey: .attributedTo)
        try container.encode(published, forKey: .published)
        try container.encodeIfPresent(updated, forKey: .updated)
        try container.encodeIfPresent(proof, forKey: .proof)
        try container.encodeIfPresent(peerID, forKey: .peerID)
        try container.encodeIfPresent(publicKey, forKey: .publicKey)
        if !clubs.isEmpty { try container.encode(clubs, forKey: .clubs) }

        // Encode wawaExtensions as top-level keys
        try Profile.encodeWawaExtensions(wawaExtensions, to: encoder)
    }
}

// MARK: - Wawa extension coding helpers

extension WawaObject {
    /// Decode unknown keys into wawaExtensions.
    static func decodeWawaExtensions(from decoder: Decoder) throws -> [String: WawaValue] {
        // Use a dynamic container to capture all keys, then filter known ones.
        // For simplicity in Phase A, we rely on the fact that Codable ignores
        // unknown keys by default when using JSONDecoder with the default
        // keyDecodingStrategy. The wawaExtensions field is populated by
        // the WawaDecoder reading the raw JSON and extracting wawa:* fields.
        //
        // This is a deliberate simplification: standard Codable decode passes
        // through unknown keys silently. WawaDecoder handles the full
        // wawaExtensions extraction from raw JSON.
        return [:]
    }

    /// Encode wawaExtensions as top-level keys.
    static func encodeWawaExtensions(_ extensions: [String: WawaValue], to encoder: Encoder) throws {
        guard !extensions.isEmpty else { return }
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in extensions {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            try container.encode(value, forKey: codingKey)
        }
    }
}

/// A coding key that accepts any string value.
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
