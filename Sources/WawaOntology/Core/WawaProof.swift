import Foundation

/// A cryptographic proof envelope.
///
/// Follows the Verifiable Credentials proof model (Data Integrity).
/// The JSON-LD object is canonicalized via JCS (RFC 8785),
/// hashed, and signed. The proof carries the signature and the
/// verification method (a DID:key reference).
///
/// Phase A: struct only (no sign/verify implementation).
/// Phase B: Ed25519 sign/verify via CryptoKit.
public struct WawaProof: Codable, Sendable, Equatable {
    /// Signature suite identifier.
    ///
    /// Examples: `"Ed25519Signature2020"`, `"EdDSAJCS2022"`.
    public var type: String

    /// When the proof was created.
    public var created: Date

    /// DID URL of the verification method.
    ///
    /// Example: `"did:key:z6Mk...#key-1"`.
    public var verificationMethod: String

    /// Purpose of the proof.
    ///
    /// Standard values: `"assertionMethod"`, `"authentication"`,
    /// `"capabilityInvocation"`.
    public var proofPurpose: String

    /// The signature value, base58-btc or base64url encoded.
    public var proofValue: String

    public init(
        type: String = "Ed25519Signature2020",
        created: Date = Date(),
        verificationMethod: String,
        proofPurpose: String = "assertionMethod",
        proofValue: String
    ) {
        self.type = type
        self.created = created
        self.verificationMethod = verificationMethod
        self.proofPurpose = proofPurpose
        self.proofValue = proofValue
    }
}
