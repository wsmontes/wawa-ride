/// A JSON-compatible value enum for wawa:* extension fields.
///
/// Since `[String: Any]` is not Codable, this enum bridges the gap.
/// It supports all JSON value types and round-trips through Codable
/// without loss.
public enum WawaValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case object([String: WawaValue])
    case array([WawaValue])
    case null

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .integer(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([WawaValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: WawaValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "WawaValue: unsupported JSON type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):    try container.encode(s)
        case .number(let n):    try container.encode(n)
        case .integer(let i):   try container.encode(i)
        case .boolean(let b):   try container.encode(b)
        case .object(let o):    try container.encode(o)
        case .array(let a):     try container.encode(a)
        case .null:             try container.encodeNil()
        }
    }

    // MARK: - Convenience accessors

    public var stringValue: String? {
        if case .string(let s) = self { return s }; return nil
    }

    public var intValue: Int? {
        if case .integer(let i) = self { return i }; return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let n):  return n
        case .integer(let i): return Double(i)
        default:              return nil
        }
    }

    public var boolValue: Bool? {
        if case .boolean(let b) = self { return b }; return nil
    }

    public var arrayValue: [WawaValue]? {
        if case .array(let a) = self { return a }; return nil
    }

    public var objectValue: [String: WawaValue]? {
        if case .object(let o) = self { return o }; return nil
    }
}
