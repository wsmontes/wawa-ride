import Foundation
import CoreLocation

// MARK: - Ride

struct Ride: Codable, Identifiable {
    let id: String
    let name: String
    let leaderId: String
    let leaderName: String
    var status: RideStatus
    let createdAt: Date
    var finishedAt: Date?
    var currentRouteId: String?
    var currentRouteName: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        leaderId: String,
        leaderName: String
    ) {
        self.id = id
        self.name = name
        self.leaderId = leaderId
        self.leaderName = leaderName
        self.status = .active
        self.createdAt = Date()
    }
}

enum RideStatus: String, Codable {
    case active
    case paused
    case finished
}

// MARK: - Ride Participant

struct RideParticipant: Codable, Identifiable {
    var id: String { riderId }

    let riderId: String
    let name: String
    var bikeModel: String?
    var role: RideRole
    var isConnected: Bool
    var lastSeen: Date

    // Position
    var latitude: Double
    var longitude: Double
    var speed: Double
    var heading: Double
    var altitude: Double?
    var locationTimestamp: Date

    // Status
    var isMoving: Bool
    var batteryLevel: Float?
    var offlineSince: Date?
    var lastMovingAt: Date?       // When rider was last above walking speed
    var stoppedNotified: Bool = false  // Already notified about stop

    // Rooms
    var activeRooms: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude ?? 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: heading,
            speed: speed / 3.6,
            timestamp: locationTimestamp
        )
    }
}

// MARK: - Ride Summary

struct RideSummary: Codable, Identifiable {
    var id: String { rideId }
    let rideId: String
    let rideName: String
    let startedAt: Date
    let finishedAt: Date
    let totalDistance: Double?        // meters
    let totalDuration: TimeInterval?   // seconds
    let maxAltitude: Double?
    let avgSpeed: Double?             // km/h
    let riderCount: Int
    let stopCount: Int
    let alertCount: Int
    let routeId: String?
}
