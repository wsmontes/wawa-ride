import Foundation

/// Encodes WawaObject instances to JSON-LD.
///
/// The encoder wraps standard JSONEncoder output with JSON-LD
/// semantics:
/// - Adds `@context` from the object's context registry
/// - Ensures `type` is always an array: `["Event", "wawa:RideEvent"]`
/// - Omits nil values, empty arrays, and empty dictionaries
public final class WawaEncoder {
    /// Whether to produce pretty-printed output (multiline, indented).
    public var prettyPrint: Bool = false

    private let jsonEncoder: JSONEncoder

    public init() {
        jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = [.sortedKeys]
    }

    /// Encode a WawaObject to JSON-LD Data.
    public func encode<T: WawaObject>(_ object: T) throws -> Data {
        if prettyPrint {
            jsonEncoder.outputFormatting.insert(.prettyPrinted)
        }
        let jsonData = try jsonEncoder.encode(object)
        return try injectContext(into: jsonData, for: T.self)
    }

    /// Encode a WawaObject to a JSON-LD dictionary.
    public func encodeToDictionary<T: WawaObject>(_ object: T) throws -> [String: Any] {
        let data = try encode(object)
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw WawaEncodingError.notADictionary
        }
        return dict
    }

    /// Encode to a JSON-LD string (for storage, debugging).
    public func encodeToString<T: WawaObject>(_ object: T) throws -> String {
        let data = try encode(object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WawaEncodingError.utf8ConversionFailed
        }
        return string
    }

    // MARK: - Private

    /// Inject @context and normalize type array after JSONEncoder has done its work.
    private func injectContext<T: WawaObject>(into data: Data, for type: T.Type) throws -> Data {
        // Parse the JSON output from JSONEncoder
        var dict = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        // 1. Add @context
        let contextURLs = T.contexts.map(\.rawValue)
        dict["@context"] = contextURLs.count == 1
            ? contextURLs[0]
            : contextURLs

        // 2. Normalize type field: ensure it's an array with wawaType + additionalTypes
        var types: [String] = []
        if let existingType = dict["type"] as? String {
            types.append(existingType)
        } else if let existingTypes = dict["type"] as? [String] {
            types = existingTypes
        }
        // Merge with declared types (avoid duplicates)
        let declaredTypes = [T.wawaType] + T.additionalTypes
        for dt in declaredTypes {
            if !types.contains(dt) {
                types.append(dt)
            }
        }
        dict["type"] = types.count == 1 ? types[0] : types

        // 3. Clean up: remove Codable artifacts we don't want in JSON-LD
        // (wawaExtensions: empty dict → omit)
        if let exts = dict["wawaExtensions"] as? [String: Any], exts.isEmpty {
            dict.removeValue(forKey: "wawaExtensions")
        }

        let options: JSONSerialization.WritingOptions = prettyPrint
            ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]

        return try JSONSerialization.data(withJSONObject: dict, options: options)
    }
}

// MARK: - Errors

public enum WawaEncodingError: Error {
    case notADictionary
    case utf8ConversionFailed
}
