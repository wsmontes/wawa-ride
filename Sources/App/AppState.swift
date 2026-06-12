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
    @Published var currentRideCode: String?
    @Published var currentRoomId: String?
    @Published var rideStartedAt: Date?

    // Participants
    @Published var participants: [RideParticipant] = []

    // Rooms
    @Published var activeRooms: [Room] = []
    @Published var hasUnreadMessages = false

    // Maps MCPeerID displayName → senderId for offline detection
    private var peerToSenderId: [String: String] = [:]

    // Pending navigation (from ExploreMapView)
    @Published var pendingNavigationRoute: MKRoute?

    private init() {}

    // MARK: - Participant Management

    /// Disambiguate duplicate names by appending a numeric suffix.
    /// "Pedro", "Pedro" → "Pedro", "Pedro 2"
    private func disambiguateName(_ name: String, excluding senderId: String? = nil) -> String {
        let sameName = participants.filter {
            $0.riderId != (senderId ?? "") && $0.name == name
        }
        if sameName.isEmpty { return name }

        // Count how many have this base name (including self)
        let allWithName = participants.filter {
            ($0.riderId == (senderId ?? "")) || $0.name.hasPrefix(name)
        }
        let next = allWithName.count + 1
        return "\(name) \(next)"
    }

    func updateParticipant(senderId: String, senderName: String, location: LocationPayload) {
        let displayName = disambiguateName(senderName, excluding: senderId)
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
                name: displayName,
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

    /// Store MCPeerID displayName → senderId mapping for offline detection
    func mapPeerToSender(peerName: String, senderId: String) {
        peerToSenderId[peerName] = senderId
    }

    /// Mark participant as offline by MCPeerID displayName
    func setParticipantOffline(byPeerName peerName: String) {
        guard let senderId = peerToSenderId[peerName],
              let index = participants.firstIndex(where: { $0.riderId == senderId })
        else { return }
        participants[index].isConnected = false
        participants[index].offlineSince = Date()
        Logger.shared.mesh("Participant offline: \(participants[index].name) (peer: \(peerName))")
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

    // MARK: - Sweeper Confirmation

    /// Whether the sweeper has confirmed the group is complete
    @Published var sweeperConfirmedAll = false
    @Published var sweeperReportedMissing = false

    func sweeperConfirmAll() {
        sweeperConfirmedAll = true
        sweeperReportedMissing = false
        Logger.shared.ride("Sweeper confirmed: all together")

        // Notify group via mesh
        sendSweeperConfirmation(message: "✅ Grupo completo. Todos juntos.")
    }

    func sweeperReportMissing() {
        sweeperConfirmedAll = false
        sweeperReportedMissing = true
        Logger.shared.ride("Sweeper reported: someone missing")

        // Notify group via mesh
        sendSweeperConfirmation(message: "⚠️ Varredor reportou: alguém ficou para trás!")
    }

    private func sendSweeperConfirmation(message: String) {
        let payload = MeshPayload(
            type: .sweeperConfirm,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: currentRideId ?? "",
            ttl: 3,
            priority: .high,
            payload: try! JSONEncoder().encode(SweeperPayload(message: message))
        )
        TransportManager.shared.send(payload)
    }

    func reset() {
        currentRideId = nil
        currentRideName = nil
        currentRideCode = nil
        currentRoomId = nil
        participants.removeAll()
        activeRooms.removeAll()
        hasUnreadMessages = false
        sweeperConfirmedAll = false
        sweeperReportedMissing = false
    }
}
