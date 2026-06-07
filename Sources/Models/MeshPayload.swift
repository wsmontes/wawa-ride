import Foundation

// MARK: - Mesh Payload (Envelope)

struct MeshPayload: Codable {
    let id: String
    let type: MeshPayloadType
    let senderId: String
    let senderName: String
    let rideId: String
    let roomId: String?
    let timestamp: Date
    var ttl: Int
    let priority: MeshPriority
    let payload: Data

    init(
        id: String = UUID().uuidString,
        type: MeshPayloadType,
        senderId: String,
        senderName: String,
        rideId: String,
        roomId: String? = nil,
        timestamp: Date = Date(),
        ttl: Int = 5,
        priority: MeshPriority = .normal,
        payload: Data
    ) {
        self.id = id
        self.type = type
        self.senderId = senderId
        self.senderName = senderName
        self.rideId = rideId
        self.roomId = roomId
        self.timestamp = timestamp
        self.ttl = ttl
        self.priority = priority
        self.payload = payload
    }
}

enum MeshPayloadType: String, Codable {
    case locationUpdate
    case routeCreated
    case routeBatch
    case routeShared
    case roomCreated
    case roomClosed
    case roomJoin
    case roomLeave
    case voiceLive
    case voiceMessage
    case voiceMessageAck
    case hazardAlert
    case hazardConfirm
    case hazardClear
    case statusChange
    case heartbeat
    case sosAlert
    case sosCancel
    case rideInfo
    case joinRequest
    case joinAccept
    case leaveNotification
    case rideEnded
    case fullState
    case fullStateRequest
}

enum MeshPriority: Int, Codable, Comparable {
    case critical = 0
    case high = 1
    case normal = 2
    case low = 3

    static func < (lhs: MeshPriority, rhs: MeshPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Specific Payloads

struct LocationPayload: Codable {
    let lat: Double
    let lng: Double
    let speed: Double
    let heading: Double
    let altitude: Double?
    let batteryLevel: Float?
}

struct RoutePayload: Codable {
    let route: Route
}

struct RouteBatchPayload: Codable {
    let routeId: String
    let points: [RoutePoint]
    let batchStart: Int
    let batchEnd: Int
}

struct RoomPayload: Codable {
    let room: Room
}

struct RoomMembershipPayload: Codable {
    let roomId: String
    let riderId: String
    let riderName: String
}

struct VoiceLivePayload: Codable {
    let roomId: String
    let sequence: Int
    let durationMs: Int
    let audioData: Data
}

struct VoiceMessagePayload: Codable {
    let messageId: String
    let roomId: String
    let fromRiderId: String
    let fromRiderName: String
    let sentAt: Date
    let duration: TimeInterval
    let audioData: Data
}

struct VoiceMessageAckPayload: Codable {
    let messageId: String
    let riderId: String
    let type: AckType

    enum AckType: String, Codable {
        case delivered
        case played
    }
}

struct HazardAlertPayload: Codable {
    let alert: HazardAlert
}

struct HazardActionPayload: Codable {
    let alertId: String
    let riderName: String
    let riderId: String
}

struct SOSPayload: Codable {
    let lat: Double
    let lng: Double
    let reason: String?
    let batteryLevel: Float?
}

struct StatusPayload: Codable {
    let status: String  // "stopped", "moving", "need_help", "ok"
    let lat: Double
    let lng: Double
}

struct HeartbeatPayload: Codable {
    let batteryLevel: Float?
    let isMoving: Bool
    let activeRoom: String?
}

struct RideEndedPayload: Codable {
    let rideId: String
    let finishedAt: Date
}

struct FullStatePayload: Codable {
    let ride: Ride
    let participants: [RideParticipant]
    let rooms: [Room]
    let activeRoute: Route?
    let activeAlerts: [HazardAlert]
}
