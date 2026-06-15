import Foundation
import SwiftProtobuf

/// Compact protobuf-encoded location (12-14 bytes vs 80 bytes JSON).
/// Uses sfixed32 for lat/lon (degrees × 1e7 = ~1cm precision).
public struct CompactLocation: Sendable {
    public let latitudeI: Int32    // degrees × 1e7
    public let longitudeI: Int32   // degrees × 1e7
    public let heading: UInt32     // degrees 0-359
    public let speed: UInt32       // decimeters/second (0-2550 = 0-918 km/h)

    public var latitude: Double { Double(latitudeI) / 1e7 }
    public var longitude: Double { Double(longitudeI) / 1e7 }
    public var headingDegrees: Double { Double(heading) }
    public var speedMps: Double { Double(speed) / 10.0 }

    public init(latitude: Double, longitude: Double, heading: Double?, speed: Double?) {
        self.latitudeI = Int32(latitude * 1e7)
        self.longitudeI = Int32(longitude * 1e7)
        self.heading = UInt32(heading ?? 0)
        self.speed = UInt32((speed ?? 0) * 10)  // m/s → dm/s
    }

    /// Encode to compact binary (~12 bytes).
    public func encode() -> Data {
        var data = Data(capacity: 14)
        withUnsafeBytes(of: latitudeI.littleEndian) { data.append(contentsOf: $0) }   // 4
        withUnsafeBytes(of: longitudeI.littleEndian) { data.append(contentsOf: $0) }  // 4
        withUnsafeBytes(of: UInt16(heading).littleEndian) { data.append(contentsOf: $0) } // 2
        withUnsafeBytes(of: UInt16(speed).littleEndian) { data.append(contentsOf: $0) }   // 2
        return data  // 12 bytes total
    }

    /// Decode from compact binary.
    public static func decode(_ data: Data) -> CompactLocation? {
        guard data.count >= 12 else { return nil }
        let lat = data[0..<4].withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let lon = data[4..<8].withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let hdg = data[8..<10].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        let spd = data[10..<12].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        var loc = CompactLocation(latitude: 0, longitude: 0, heading: nil, speed: nil)
        return CompactLocation(
            latitudeI: lat, longitudeI: lon,
            heading: UInt32(hdg), speed: UInt32(spd)
        )
    }

    private init(latitudeI: Int32, longitudeI: Int32, heading: UInt32, speed: UInt32) {
        self.latitudeI = latitudeI
        self.longitudeI = longitudeI
        self.heading = heading
        self.speed = speed
    }
}
