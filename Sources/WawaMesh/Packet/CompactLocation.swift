import Foundation

/// Compact 12-byte location encoding for BLE mesh transmission.
///
/// Uses the same approach as Meshtastic's Position protobuf:
/// https://github.com/meshtastic/protobufs/blob/master/meshtastic/mesh.proto
///
/// Encoding: lat/lon as sfixed32 (degrees × 1e7) gives ~1.1cm precision.
/// This is the standard approach used by GPS protocols (NMEA, Meshtastic, etc.).
///
/// Size comparison:
/// - JSON LocationPayload: ~80 bytes (lat, lon, heading, speed, accuracy, timestamp)
/// - CompactLocation:       12 bytes (lat, lon, heading, speed)
/// - Reduction: 85% smaller → NEVER needs BLE fragmentation (MTU = 469 bytes)
///
/// Wire format (little-endian, no tags, no schema overhead):
/// ```
/// [lat_i:4][lon_i:4][heading:2][speed:2] = 12 bytes
/// ```
///
/// Reference: StackOverflow discussion on delta encoding GPS coordinates
/// https://stackoverflow.com/questions/3947151/compressing-gps-data
/// "3 bytes per coordinate is sufficient for ~2m precision"
/// We use 4 bytes (sfixed32 × 1e7) for ~1cm — overkill but matches Meshtastic.
public struct CompactLocation: Sendable {
    public let latitudeI: Int32    // degrees × 1e7
    public let longitudeI: Int32   // degrees × 1e7
    public let heading: UInt32     // degrees 0-359
    public let speed: UInt32       // decimeters/second (0.1 m/s resolution)

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

    /// Encode to 12 bytes (little-endian, no framing).
    public func encode() -> Data {
        var data = Data(capacity: 12)
        withUnsafeBytes(of: latitudeI.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: longitudeI.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(heading).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(speed).littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// Decode from 12-byte binary.
    public static func decode(_ data: Data) -> CompactLocation? {
        guard data.count >= 12 else { return nil }
        let lat = data[0..<4].withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let lon = data[4..<8].withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let hdg = data[8..<10].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        let spd = data[10..<12].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        return CompactLocation(latitudeI: lat, longitudeI: lon, heading: UInt32(hdg), speed: UInt32(spd))
    }

    private init(latitudeI: Int32, longitudeI: Int32, heading: UInt32, speed: UInt32) {
        self.latitudeI = latitudeI
        self.longitudeI = longitudeI
        self.heading = heading
        self.speed = speed
    }
}
