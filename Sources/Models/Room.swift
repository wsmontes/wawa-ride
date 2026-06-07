import Foundation

// MARK: - Room (Communication Channel)

struct Room: Codable, Identifiable, Hashable {
    let id: String
    let rideId: String
    let name: String
    let createdBy: String
    let creatorName: String
    let createdAt: Date
    let type: RoomType
    let isPrivate: Bool
    var members: [String]
    var isActive: Bool

    init(
        id: String = UUID().uuidString,
        rideId: String,
        name: String,
        createdBy: String,
        creatorName: String,
        type: RoomType,
        isPrivate: Bool = false,
        members: [String] = [],
        isActive: Bool = true
    ) {
        self.id = id
        self.rideId = rideId
        self.name = name
        self.createdBy = createdBy
        self.creatorName = creatorName
        self.createdAt = Date()
        self.type = type
        self.isPrivate = isPrivate
        self.members = members
        self.isActive = isActive
    }

    static func generalRoom(rideId: String, leaderId: String, leaderName: String) -> Room {
        Room(
            id: "\(rideId)-general",
            rideId: rideId,
            name: "Geral",
            createdBy: leaderId,
            creatorName: leaderName,
            type: .general,
            isPrivate: false,
            members: [leaderId]
        )
    }

    static func alertsRoom(rideId: String) -> Room {
        Room(
            id: "\(rideId)-alerts",
            rideId: rideId,
            name: "Alertas",
            createdBy: "system",
            creatorName: "WAWA",
            type: .alerts,
            isPrivate: false
        )
    }

    static func directRoom(rideId: String, riderId: String, riderName: String, peerId: String, peerName: String) -> Room {
        Room(
            id: "\(rideId)-dm-\([riderId, peerId].sorted().joined(separator: "-"))",
            rideId: rideId,
            name: peerName,
            createdBy: riderId,
            creatorName: riderName,
            type: .direct,
            isPrivate: true,
            members: [riderId, peerId]
        )
    }
}

enum RoomType: String, Codable, CaseIterable {
    case general       // Auto-created with ride. Everyone is in it.
    case voice         // Live voice room
    case messaging     // Async voice messages only
    case alerts        // System alerts (hazards, SOS, status)
    case direct        // Private conversation between 2 riders
}

// MARK: - Voice Message

struct VoiceMessage: Codable, Identifiable {
    let id: String
    let roomId: String
    let rideId: String
    let fromRiderId: String
    let fromRiderName: String
    let sentAt: Date
    let duration: TimeInterval
    let audioData: Data
    var deliveredTo: [String]
    var playedBy: [String]

    var isPlayedByMe: Bool {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        return playedBy.contains(myId)
    }

    var isDeliveredToMe: Bool {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        return deliveredTo.contains(myId)
    }
}
