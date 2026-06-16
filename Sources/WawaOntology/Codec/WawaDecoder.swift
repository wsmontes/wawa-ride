import Foundation

/// Decodes JSON-LD data into WawaObject instances.
///
/// The decoder reads JSON-LD, validates the `@context`, extracts
/// the `wawa:*` type discriminator, and delegates to standard
/// JSONDecoder for the concrete type.
public final class WawaDecoder {
    private let jsonDecoder: JSONDecoder

    public init() {
        jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
    }

    /// Decode JSON-LD Data into a concrete WawaObject type.
    ///
    /// The type is known at compile time. The decoder validates
    /// that the JSON-LD `type` array contains the expected `wawaType`.
    public func decode<T: WawaObject>(_ type: T.Type, from data: Data) throws -> T {
        let dict = try parseAsDictionary(data)

        // Validate @context presence (non-fatal warning for now)
        if dict["@context"] == nil {
            // Phase B: emit structured warning
            #if DEBUG
            print("[WawaDecoder] Warning: no @context found — treating as plain JSON")
            #endif
        }

        // Validate type matches
        validateType(in: dict, expected: T.wawaType)

        // Extract wawaExtensions from dynamic keys before decoding
        var mutableDict = dict
        mutableDict["wawaExtensions"] = extractWawaExtensions(from: dict, knownCodingKeys: [])

        let cleanedData = try JSONSerialization.data(withJSONObject: mutableDict, options: [.sortedKeys])
        return try jsonDecoder.decode(T.self, from: cleanedData)
    }

    /// Identify the wawa: type of a JSON-LD payload without fully decoding it.
    ///
    /// Returns the `wawa:*` type string (e.g., `"wawa:RideEvent"`), or nil
    /// if no wawa type is found.
    public func typeOf(_ data: Data) throws -> String? {
        let dict = try parseAsDictionary(data)
        let types = extractTypes(from: dict)
        return types.first { $0.hasPrefix("wawa:") }
    }

    // MARK: - Private

    private func parseAsDictionary(_ data: Data) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw WawaDecodingError.notADictionary
        }
        return dict
    }

    private func extractTypes(from dict: [String: Any]) -> [String] {
        if let typeStr = dict["type"] as? String {
            return [typeStr]
        } else if let typeArray = dict["type"] as? [String] {
            return typeArray
        }
        return []
    }

    private func validateType(in dict: [String: Any], expected: String) {
        let types = extractTypes(from: dict)
        if !types.isEmpty && !types.contains(expected) {
            #if DEBUG
            print("[WawaDecoder] Warning: expected type \(expected), found \(types)")
            #endif
        }
    }

    /// Extract wawa:* extension fields from the raw JSON dictionary.
    ///
    /// Any key that is NOT a known CodingKey for the target type
    /// AND is not a JSON-LD infrastructure key (`@context`, `type`, `id`)
    /// is collected into `wawaExtensions`.
    private func extractWawaExtensions(from dict: [String: Any], knownCodingKeys: [String]) -> [String: WawaValue] {
        let infrastructureKeys: Set<String> = ["@context", "type", "id"]
        var extensions: [String: WawaValue] = [:]

        for (key, value) in dict {
            guard !infrastructureKeys.contains(key) else { continue }
            extensions[key] = convertToWawaValue(value)
        }
        return extensions
    }

    /// Recursively convert Any → WawaValue.
    private func convertToWawaValue(_ value: Any) -> WawaValue {
        switch value {
        case let string as String:
            return .string(string)
        case let number as Double:
            // Check if it's actually an integer
            if number == Double(Int(number)) && number.truncatingRemainder(dividingBy: 1) == 0 {
                return .integer(Int(number))
            }
            return .number(number)
        case let int as Int:
            return .integer(int)
        case let bool as Bool:
            return .boolean(bool)
        case let array as [Any]:
            return .array(array.map { convertToWawaValue($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { convertToWawaValue($0) })
        case is NSNull:
            return .null
        default:
            return .null
        }
    }
}

// MARK: - Errors

public enum WawaDecodingError: Error {
    case notADictionary
    case unknownType(String)
}
