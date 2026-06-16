/// Known JSON-LD contexts for the Wawa Personal Object Model.
///
/// Every WawaObject carries one or more contexts. The base set is
/// ActivityStreams (social grammar), Schema.org (common vocabulary),
/// and Wawa v1 (extensions). VerifiableCredentials is added when
/// the object is a credential.
public enum WawaContext: String, Codable, Sendable, CaseIterable {
    /// Activity Streams 2.0 — social grammar (Object, Activity, Collection, etc.)
    case activityStreams = "https://www.w3.org/ns/activitystreams"

    /// Schema.org — common vocabulary (Person, Event, Place, Organization, etc.)
    case schemaOrg = "https://schema.org"

    /// Verifiable Credentials v2 — credential data model
    case credentialsV2 = "https://www.w3.org/ns/credentials/v2"

    /// Wawa Personal Ontology v1 — wawa:* extensions
    case wawaV1 = "https://wawa.social/ns/v1"

    /// Short alias for JSON-LD compaction.
    public var alias: String {
        switch self {
        case .activityStreams: "as"
        case .schemaOrg:        "schema"
        case .credentialsV2:    "vc"
        case .wawaV1:           "wawa"
        }
    }
}
