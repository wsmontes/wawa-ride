import Foundation

/// JSON Canonicalization Scheme (RFC 8785) — Phase A stub.
///
/// JCS produces a canonical, deterministic JSON representation
/// suitable for cryptographic hashing and signing. The full spec
/// covers:
///
/// - Object key sorting (lexicographic by UTF-16 code unit)
/// - Whitespace normalization (no insignificant whitespace)
/// - Number normalization (no exponential, no trailing zeros)
/// - Unicode escape normalization (uppercase hex, minimum length)
///
/// Phase A implements key sorting and whitespace stripping.
/// Phase B adds full RFC 8785 compliance (number normalization,
/// Unicode NFKC, escape normalization).
public enum JCS {

    /// Canonicalize JSON data per RFC 8785 (Phase A subset).
    ///
    /// - Parameter data: UTF-8 encoded JSON data.
    /// - Returns: Canonical UTF-8 bytes ready for hashing.
    /// - Throws: If the input is not valid JSON.
    public static func canonicalize(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        let canonical = canonicalizeValue(object)
        return try JSONSerialization.data(
            withJSONObject: canonical,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// Canonicalize a JSON value recursively.
    private static func canonicalizeValue(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            // Dictionary keys are already sorted by .sortedKeys above.
            // Recursively canonicalize all values.
            return dict.mapValues { canonicalizeValue($0) }

        case let array as [Any]:
            // Arrays preserve order per RFC 8785.
            return array.map { canonicalizeValue($0) }

        case let string as String:
            // Phase A: pass through. Phase B: normalize Unicode escapes.
            return string

        case let number as NSNumber:
            // Phase A: pass through. Phase B: normalize number format.
            // (No exponential notation, no trailing zeros, integer as integer)
            return number

        case is NSNull:
            return NSNull()

        default:
            return value
        }
    }

    /// Convenience: canonicalize and hash in one step.
    ///
    /// - Parameter data: UTF-8 encoded JSON data.
    /// - Returns: SHA-256 digest (32 bytes).
    public static func hash(_ data: Data) throws -> Data {
        let canonical = try canonicalize(data)
        return SHA256.digest(canonical)
    }
}

// MARK: - SHA-256 (minimal, no CryptoKit dependency for Phase A)

private enum SHA256 {
    static func digest(_ data: Data) -> Data {
        var hasher = SHA256Hasher()
        hasher.update(data)
        return hasher.finalize()
    }
}

/// Minimal SHA-256 implementation for Phase A JCS hashing.
/// Replaced by CryptoKit in Phase B when Ed25519 keys are added.
private struct SHA256Hasher {
    private var h: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]
    private var data: [UInt8] = []
    private var totalBits: UInt64 = 0

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    mutating func update(_ data: Data) {
        self.data.append(contentsOf: data)
        totalBits += UInt64(data.count) * 8
        while self.data.count >= 64 {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let offset = i * 4
                w[i] = (UInt32(self.data[offset]) << 24)
                     | (UInt32(self.data[offset + 1]) << 16)
                     | (UInt32(self.data[offset + 2]) << 8)
                     | UInt32(self.data[offset + 3])
            }
            for i in 16..<64 {
                let s0 = rightRotate(w[i - 15], 7) ^ rightRotate(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rightRotate(w[i - 2], 17) ^ rightRotate(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hi = h[7]
            for i in 0..<64 {
                let s1 = rightRotate(e, 6) ^ rightRotate(e, 11) ^ rightRotate(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hi &+ s1 &+ ch &+ SHA256Hasher.k[i] &+ w[i]
                let s0 = rightRotate(a, 2) ^ rightRotate(a, 13) ^ rightRotate(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                hi = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hi
            self.data.removeFirst(64)
        }
    }

    func finalize() -> Data {
        var data = self.data
        let totalBits = self.totalBits
        data.append(0x80)
        while (data.count + 8) % 64 != 0 { data.append(0) }
        for i in (0..<8).reversed() {
            data.append(UInt8((totalBits >> (i * 8)) & 0xff))
        }
        var hasher = SHA256Hasher()
        hasher.data = data
        hasher.totalBits = 0
        while hasher.data.count >= 64 {
            hasher.update(Data())
        }
        var result = Data()
        for hi in hasher.h {
            result.append(contentsOf: [
                UInt8((hi >> 24) & 0xff),
                UInt8((hi >> 16) & 0xff),
                UInt8((hi >> 8) & 0xff),
                UInt8(hi & 0xff)
            ])
        }
        return result
    }
}

private func rightRotate(_ value: UInt32, _ amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
}
