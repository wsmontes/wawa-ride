import Foundation

extension Data {
    /// Hex string representation of data.
    public var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Initialize from hex string.
    public init?(hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var data = Data(capacity: chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            data.append(byte)
        }
        self = data
    }
}
