import Foundation
import CoreLocation

/// A rider in the group — sourced from a remote peer.
struct Rider: Identifiable, Hashable {
    let id: String
    let displayName: String
    var coordinate: CLLocationCoordinate2D
    var heading: CLLocationDirection?
    var speed: CLLocationSpeed?
    var lastUpdate: Date
    var isConnected: Bool

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Rider, rhs: Rider) -> Bool { lhs.id == rhs.id }
}
