import Foundation
import CoreLocation
import MapKit

// MARK: - App State (Global)

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Current ride
    @Published var currentRideId: String?
    @Published var currentRideName: String?
    @Published var currentRoomId: String?
    @Published var rideStartedAt: Date?

    // Participants
    @Published var participants: [RideParticipant] = []

    // Rooms
    @Published var activeRooms: [Room] = []
    @Published var hasUnreadMessages = false

    // Pending navigation (from ExploreMapView)
    @Published var pendingNavigationRoute: MKRoute?

    private init() {}

    // MARK: - Participant Management

    func updateParticipant(senderId: String, senderName: String, location: LocationPayload) {
        if let index = participants.firstIndex(where: { $0.riderId == senderId }) {
            participants[index].latitude = location.lat
            participants[index].longitude = location.lng
            participants[index].speed = location.speed
            participants[index].heading = location.heading
            participants[index].altitude = location.altitude
            participants[index].batteryLevel = location.batteryLevel
            participants[index].locationTimestamp = Date()
            let wasMoving = participants[index].isMoving
            let nowMoving = location.speed > 5
            participants[index].isMoving = nowMoving
            if nowMoving {
                participants[index].lastMovingAt = Date()
                participants[index].stoppedNotified = false // reset when they move again
            } else if wasMoving && !nowMoving {
                participants[index].lastMovingAt = Date() // just stopped now
            }
            participants[index].isConnected = true
            participants[index].lastSeen = Date()
            participants[index].offlineSince = nil
        } else {
            var participant = RideParticipant(
                riderId: senderId,
                name: senderName,
                bikeModel: nil,
                role: .rider,
                isConnected: true,
                lastSeen: Date(),
                latitude: location.lat,
                longitude: location.lng,
                speed: location.speed,
                heading: location.heading,
                altitude: location.altitude,
                locationTimestamp: Date(),
                isMoving: location.speed > 5,
                batteryLevel: location.batteryLevel,
                activeRooms: [activeRooms.first(where: { $0.type == .general })?.id ?? "general"]
            )
            participants.append(participant)
        }
    }

    func addParticipant(_ participant: RideParticipant) {
        guard !participants.contains(where: { $0.riderId == participant.riderId }) else { return }
        participants.append(participant)
    }

    func removeParticipant(_ riderId: String) {
        participants.removeAll { $0.riderId == riderId }
    }

    func setParticipantOffline(_ riderId: String) {
        guard let index = participants.firstIndex(where: { $0.riderId == riderId }) else { return }
        participants[index].isConnected = false
        participants[index].offlineSince = Date()
    }

    func roomName(for roomId: String) -> String {
        activeRooms.first { $0.id == roomId }?.name ?? "Sala"
    }

    // MARK: - Distance & Safety

    /// Distance in meters from user location to a participant
    func distanceTo(_ participant: RideParticipant) -> CLLocationDistance? {
        guard let myLoc = LocationService.shared.currentLocation else { return nil }
        return myLoc.distance(from: participant.clLocation)
    }

    /// Participants sorted by distance from current user (closest first)
    func participantsByDistance() -> [(RideParticipant, CLLocationDistance)] {
        guard let myLoc = LocationService.shared.currentLocation else { return [] }
        return participants
            .filter { $0.isConnected }
            .map { ($0, myLoc.distance(from: $0.clLocation)) }
            .sorted { $0.1 < $1.1 }
    }

    /// Check for riders who have been stopped for more than threshold (default 2 min).
    /// Returns list of stopped riders that haven't been notified yet.
    func checkStoppedRiders(threshold: TimeInterval = 120) -> [RideParticipant] {
        let now = Date()
        return participants.filter { p in
            guard p.isConnected, !p.isMoving, !p.stoppedNotified else { return false }
            guard let lastMoving = p.lastMovingAt else { return false }
            return now.timeIntervalSince(lastMoving) > threshold
        }
    }

    /// Mark a rider as notified for the current stop
    func markStoppedNotified(_ riderId: String) {
        guard let idx = participants.firstIndex(where: { $0.riderId == riderId }) else { return }
        participants[idx].stoppedNotified = true
    }

    /// Human-readable distance string
    func distanceString(_ participant: RideParticipant) -> String {
        guard let dist = distanceTo(participant) else { return "—" }
        if dist < 10 { return "perto" }
        if dist < 1000 { return "\(Int(dist))m" }
        return String(format: "%.1f km", dist / 1000)
    }

    func reset() {
        currentRideId = nil
        currentRideName = nil
        currentRoomId = nil
        participants.removeAll()
        activeRooms.removeAll()
        hasUnreadMessages = false
    }
}
