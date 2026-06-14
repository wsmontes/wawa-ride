import Foundation
import CoreLocation

/// Compact location update sent over WebRTC DataChannel.
struct LocationUpdate: Codable {
    let lat: Double
    let lon: Double
    let heading: Double?
    let speed: Double?
    let timestamp: TimeInterval
    let riderID: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(riderID: String, location: CLLocation) {
        self.riderID = riderID
        self.lat = location.coordinate.latitude
        self.lon = location.coordinate.longitude
        self.heading = location.course >= 0 ? location.course : nil
        self.speed = location.speed >= 0 ? location.speed : nil
        self.timestamp = location.timestamp.timeIntervalSince1970
    }

    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> LocationUpdate? {
        try? JSONDecoder().decode(LocationUpdate.self, from: data)
    }
}
