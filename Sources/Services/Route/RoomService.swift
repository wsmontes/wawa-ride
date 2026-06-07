import Foundation

// MARK: - Room Service

/// Manages room lifecycle: creation, membership, messaging.

@MainActor
final class RoomService: ObservableObject {
    static let shared = RoomService()

    @Published var rooms: [Room] = []
    @Published var currentRoom: Room?

    // Voice messages by room
    @Published var messagesByRoom: [String: [VoiceMessage]] = [:]

    private override init() {}

    // MARK: - Room Creation

    func createRoom(name: String, type: RoomType, isPrivate: Bool, memberIds: [String]) -> Room? {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""
        let rideId = AppState.shared.currentRideId ?? ""

        let room = Room(
            rideId: rideId,
            name: name,
            createdBy: myId,
            creatorName: myName,
            type: type,
            isPrivate: isPrivate,
            members: [myId] + memberIds
        )

        rooms.append(room)
        try? LocalStore.shared.saveRoom(room)
        sendRoomToMesh(room)

        return room
    }

    func createDirectRoom(with riderId: String, riderName: String) -> Room? {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""
        let rideId = AppState.shared.currentRideId ?? ""

        // Check if direct room already exists
        if let existing = rooms.first(where: {
            $0.type == .direct && $0.members.contains(riderId) && $0.members.contains(myId)
        }) {
            return existing
        }

        let room = Room.directRoom(
            rideId: rideId,
            riderId: myId,
            riderName: myName,
            peerId: riderId,
            peerName: riderName
        )

        rooms.append(room)
        try? LocalStore.shared.saveRoom(room)
        sendRoomToMesh(room)

        return room
    }

    // MARK: - Default Rooms

    func createDefaultRooms(rideId: String) {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""

        let general = Room.generalRoom(rideId: rideId, leaderId: myId, leaderName: myName)
        let alerts = Room.alertsRoom(rideId: rideId)

        rooms = [general, alerts]
        try? LocalStore.shared.saveRoom(general)
        try? LocalStore.shared.saveRoom(alerts)
    }

    // MARK: - Membership

    func joinRoom(_ room: Room) {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""

        guard let index = rooms.firstIndex(where: { $0.id == room.id }),
              !rooms[index].members.contains(myId)
        else { return }

        rooms[index].members.append(myId)
        try? LocalStore.shared.saveRoom(rooms[index])
        sendMembershipToMesh(roomId: room.id, riderId: myId, riderName: myName, action: .join)
    }

    func leaveRoom(_ room: Room) {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""

        // Can't leave General or Alerts
        guard room.type != .general, room.type != .alerts else { return }

        guard let index = rooms.firstIndex(where: { $0.id == room.id }) else { return }
        rooms[index].members.removeAll { $0 == myId }
        try? LocalStore.shared.saveRoom(rooms[index])
        sendMembershipToMesh(roomId: room.id, riderId: myId, riderName: myName, action: .leave)
    }

    func closeRoom(_ room: Room) {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""

        // Only creator can close
        guard room.createdBy == myId, room.type != .general, room.type != .alerts else { return }

        guard let index = rooms.firstIndex(where: { $0.id == room.id }) else { return }
        rooms[index].isActive = false
        try? LocalStore.shared.saveRoom(rooms[index])
        sendRoomClosedToMesh(room)

        if rooms.count > index {
            rooms.remove(at: index)
        }
    }

    // MARK: - Messages

    func loadMessages(for roomId: String) -> [VoiceMessage] {
        LocalStore.shared.loadVoiceMessages(for: roomId)
    }

    func addMessage(_ message: VoiceMessage) {
        var msgs = messagesByRoom[message.roomId] ?? []
        msgs.append(message)
        messagesByRoom[message.roomId] = msgs
    }

    // MARK: - Incoming from Mesh

    func handleIncomingRoom(_ room: Room) {
        guard !rooms.contains(where: { $0.id == room.id }) else { return }
        rooms.append(room)
        try? LocalStore.shared.saveRoom(room)

        // TTS notification
        VoiceAssistant.shared.speak(.roomCreated(name: room.name, by: room.creatorName))
    }

    func handleRoomClosed(_ roomId: String) {
        rooms.removeAll { $0.id == roomId }
    }

    func handleMembershipChange(roomId: String, riderId: String, riderName: String, action: RoomMembershipAction) {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else { return }

        switch action {
        case .join:
            if !rooms[index].members.contains(riderId) {
                rooms[index].members.append(riderId)
            }
        case .leave:
            rooms[index].members.removeAll { $0 == riderId }
        }

        try? LocalStore.shared.saveRoom(rooms[index])
    }

    // MARK: - Send via Mesh

    private func sendRoomToMesh(_ room: Room) {
        let payload = RoomPayload(room: room)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let meshPayload = MeshPayload(
            type: .roomCreated,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            roomId: room.id,
            ttl: 10,
            priority: .high,
            payload: data
        )

        TransportManager.shared.send(meshPayload)
    }

    private func sendRoomClosedToMesh(_ room: Room) {
        let payload = RoomMembershipPayload(roomId: room.id, riderId: "", riderName: "")
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let meshPayload = MeshPayload(
            type: .roomClosed,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            roomId: room.id,
            ttl: 10,
            priority: .high,
            payload: data
        )

        TransportManager.shared.send(meshPayload)
    }

    private func sendMembershipToMesh(roomId: String, riderId: String, riderName: String, action: RoomMembershipAction) {
        let payload = RoomMembershipPayload(roomId: roomId, riderId: riderId, riderName: riderName)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let type: MeshPayloadType = action == .join ? .roomJoin : .roomLeave

        let meshPayload = MeshPayload(
            type: type,
            senderId: riderId,
            senderName: riderName,
            rideId: AppState.shared.currentRideId ?? "",
            roomId: roomId,
            ttl: 5,
            priority: .normal,
            payload: data
        )

        TransportManager.shared.send(meshPayload)
    }
}

enum RoomMembershipAction {
    case join
    case leave
}
