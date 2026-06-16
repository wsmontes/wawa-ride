import Foundation

/// Factory for Wawa object identifiers — URNs, DIDs, and peer references.
///
/// Identifiers follow this scheme:
/// - Local objects: `urn:wawa:<type>:<base62-random>`
/// - Mesh peers: `urn:wawa:peer:<hex-peer-id>`
/// - Cryptographic identities: `did:key:<multibase>` (Phase B)
public enum WawaIdentifier {

    // MARK: - Generation

    /// Create a new URN for a local Wawa object.
    ///
    /// Format: `urn:wawa:<type>:<12-char-base62-suffix>`
    /// Example: `urn:wawa:ride:01HX3K9M2Qv7`
    public static func make(type: String) -> String {
        let suffix = Self.randomBase62(length: 12)
        return "urn:wawa:\(type):\(suffix)"
    }

    /// Create a peer URN from the 8-byte mesh PeerID.
    ///
    /// Format: `urn:wawa:peer:<hex-encoded>`
    /// Example: `urn:wawa:peer:a1b2c3d4e5f6g7h8`
    public static func peer(_ peerID: Data) -> String {
        "urn:wawa:peer:\(peerID.hexEncodedString())"
    }

    /// Create a DID:key identifier from an Ed25519 public key (Phase B).
    ///
    /// Format: `did:key:z<multibase-base58btc>`
    public static func didKey(publicKey: Data) -> String {
        // Placeholder — Phase B implements proper multibase encoding
        "did:key:z\(publicKey.hexEncodedString())"
    }

    // MARK: - Parsing

    /// Extract the type component from a Wawa URN.
    ///
    /// For `urn:wawa:ride:01HX...`, returns `"ride"`.
    public static func typeComponent(from id: String) -> String? {
        guard id.hasPrefix("urn:wawa:") else { return nil }
        let parts = id.dropFirst("urn:wawa:".count).split(separator: ":", maxSplits: 1)
        return parts.first.map(String.init)
    }

    /// Returns true if the identifier is a Wawa URN.
    public static func isWawaURN(_ id: String) -> Bool {
        id.hasPrefix("urn:wawa:")
    }

    /// Returns true if the identifier is a DID.
    public static func isDID(_ id: String) -> Bool {
        id.hasPrefix("did:")
    }

    // MARK: - Private

    private static let base62Chars = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    )

    private static func randomBase62(length: Int) -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            base62Chars[Int(rng.next() % 62)]
        })
    }
}

// MARK: - Note: hexEncodedString() provided by BitFoundation/Data+Hex.swift
