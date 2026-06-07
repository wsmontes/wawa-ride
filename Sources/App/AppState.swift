import Foundation
import CoreLocation

// MARK: - App State (Global)

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Current ride
    @Published var currentRideId: String?
    @Published var currentRideName: String?
    @Published var currentRoomId: String?

    // Participants
    @Published var participants: [RideParticipant] = []

    // Rooms
    @Published var activeRooms: [Room] = []
    @Published var hasUnreadMessages = false

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
            participants[index].isMoving = location.speed > 5
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

    func reset() {
        currentRideId = nil
        currentRideName = nil
        currentRoomId = nil
        participants.removeAll()
        activeRooms.removeAll()
        hasUnreadMessages = false
    }
}
