import Foundation
import CoreLocation

// MARK: - Route

struct Route: Codable, Identifiable {
    let id: String
    let name: String
    let createdBy: String
    let createdAt: Date
    let source: RouteSource
    var waypoints: [RouteWaypoint]
    var simplifiedTrack: [RoutePoint]?
    var totalDistance: Double?
    var estimatedDuration: TimeInterval?
    var elevationGain: Double?
    var tags: [String]

    init(
        id: String = UUID().uuidString,
        name: String,
        createdBy: String,
        source: RouteSource,
        waypoints: [RouteWaypoint] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.createdAt = Date()
        self.source = source
        self.waypoints = waypoints
        self.tags = tags
    }
}

enum RouteSource: String, Codable {
    case recorded     // Recorded live (leader's track)
    case drawn        // Manually placed waypoints
    case imported     // .GPX import
    case shared       // Received from another rider via mesh
}

// MARK: - Route Waypoint

struct RouteWaypoint: Codable, Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let order: Int
    var name: String?
    var type: WaypointType
    var isStop: Bool
    var stopDuration: TimeInterval?

    init(
        id: String = UUID().uuidString,
        latitude: Double,
        longitude: Double,
        order: Int,
        name: String? = nil,
        type: WaypointType = .waypoint,
        isStop: Bool = false,
        stopDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.order = order
        self.name = name
        self.type = type
        self.isStop = isStop
        self.stopDuration = stopDuration
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum WaypointType: String, Codable, CaseIterable {
    case start
    case waypoint
    case stop
    case finish
}

// MARK: - Route Point (track point)

struct RoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let order: Int
    let timestamp: Date?
    let speed: Double?
    let altitude: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
