import Foundation

/// The core protocol for every object in the Wawa Personal Object Model.
///
/// Conforming types are portable JSON-LD objects compatible with ActivityStreams,
/// Schema.org, DID/VC, Nostr, and ATProto. The protocol captures the common
/// intersection of these standards.
///
/// ## Field Preference Order
///
/// 1. ActivityStreams → `attributedTo`, `published`, `updated`, `name`, `summary`, `content`
/// 2. Schema.org → `Person`, `Event`, `Place`, `Organization`, `ImageObject`
/// 3. DID → `id` (for identity objects)
/// 4. Verifiable Credentials → `proof`, `issuer`, `credentialSubject`
/// 5. Wawa extensions → `wawa:*` fields in `wawaExtensions`
///
/// ## Three Forms, One Object
///
/// - **Portable:** JSON-LD with `@context` — storage, export, human readable
/// - **Signable:** JCS canonicalized + `proof` — cryptographic verification
/// - **Transport:** Protocol-specific projection — BLE binary, Nostr event, AP activity
public protocol WawaObject: Codable, Sendable, Identifiable where ID == String {
    /// JSON-LD contexts for this object type.
    ///
    /// Always includes at least `[.activityStreams, .schemaOrg, .wawaV1]`.
    /// Credential types add `.credentialsV2`.
    static var contexts: [WawaContext] { get }

    /// Primary type identifier in the `wawa:` namespace.
    ///
    /// Examples: `"wawa:Profile"`, `"wawa:RideEvent"`, `"wawa:Place"`.
    static var wawaType: String { get }

    /// Additional types from ActivityStreams or Schema.org.
    ///
    /// Examples: `["Person"]`, `["Event"]`, `["Place"]`, `["OrderedCollection"]`.
    static var additionalTypes: [String] { get }

    // MARK: - Core fields (common intersection)

    /// Globally unique identifier.
    ///
    /// Can be a Wawa URN (`urn:wawa:ride:01HX...`), a DID (`did:key:z6Mk...`),
    /// or a URL. This is the object's canonical identity across all protocols.
    var id: String { get }

    /// Who created or emitted this object.
    ///
    /// ActivityStreams canonical term. Maps to:
    /// - AS2: `actor` / `attributedTo`
    /// - Schema.org: `author` / `creator`
    /// - DID/VC: `issuer`
    /// - Nostr: `pubkey`
    var attributedTo: String? { get }

    /// When the object was first published.
    ///
    /// Maps to:
    /// - AS2: `published`
    /// - Schema.org: `datePublished`
    /// - Nostr: `created_at`
    var published: Date { get }

    /// When the object was last modified.
    ///
    /// `nil` if never modified since creation.
    /// Maps to:
    /// - AS2: `updated`
    /// - Schema.org: `dateModified`
    var updated: Date? { get }

    /// Cryptographic proof (JCS + signature).
    ///
    /// `nil` for unsigned objects. Present when the object has been
    /// canonicalized and signed by its `attributedTo` identity.
    var proof: WawaProof? { get set }

    /// Extension fields under the `wawa:` namespace.
    ///
    /// These are fields that don't exist in ActivityStreams or Schema.org.
    /// They're serialized as top-level keys with the `wawa:` prefix stripped
    /// (the `@context` resolves them to the full IRI).
    var wawaExtensions: [String: WawaValue] { get set }
}

// MARK: - Default implementations

extension WawaObject {
    /// Default contexts for most non-credential objects.
    public static var contexts: [WawaContext] {
        [.activityStreams, .schemaOrg, .wawaV1]
    }

    /// Additional types default to empty.
    public static var additionalTypes: [String] { [] }

    /// Decode unknown keys into wawaExtensions.
    /// Phase A: returns empty dict. WawaDecoder handles full extraction.
    static func decodeWawaExtensions(from decoder: Decoder) throws -> [String: WawaValue] {
        return [:]
    }

    /// Encode wawaExtensions as top-level keys using DynamicCodingKey.
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
