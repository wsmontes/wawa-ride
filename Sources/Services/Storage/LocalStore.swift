import Foundation
import GRDB

// MARK: - Local Store (GRDB/SQLite)

final class LocalStore: @unchecked Sendable {
    static let shared = LocalStore()

    private var dbQueue: DatabaseQueue!

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsDir.appendingPathComponent("wawa.sqlite").path

        do {
            dbQueue = try DatabaseQueue(path: dbPath)
            try createTables()
        } catch {
            // Try in-memory database as fallback
            print("📦 LocalStore disk setup failed: \(error). Using in-memory DB.")
            do {
                dbQueue = try DatabaseQueue()
                try createTables()
            } catch {
                assertionFailure("LocalStore: both disk and memory DB failed: \(error)")
                dbQueue = try! DatabaseQueue() // last resort — will crash if this fails
            }
        }
    }

    private func createTables() throws {
        try dbQueue.write { db in
            // Rides
            try db.create(table: "rides", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("leader_id", .text).notNull()
                t.column("leader_name", .text).notNull()
                t.column("status", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("finished_at", .double)
                t.column("current_route_id", .text)
                t.column("current_route_name", .text)
            }

            // Routes
            try db.create(table: "routes", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("created_by", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("source", .text).notNull()
                t.column("waypoints_json", .text).notNull()
                t.column("track_json", .text)
                t.column("simplified_track_json", .text)
                t.column("total_distance", .double)
                t.column("estimated_duration", .double)
                t.column("elevation_gain", .double)
                t.column("tags", .text)
            }

            // Rooms (volatile, for current ride)
            try db.create(table: "rooms", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("ride_id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("created_by", .text).notNull()
                t.column("creator_name", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("type", .text).notNull()
                t.column("is_private", .boolean).notNull()
                t.column("members_json", .text).notNull()
                t.column("is_active", .boolean).notNull()
            }

            // Voice messages
            try db.create(table: "voice_messages", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("room_id", .text).notNull()
                t.column("ride_id", .text).notNull()
                t.column("from_rider_id", .text).notNull()
                t.column("from_rider_name", .text).notNull()
                t.column("sent_at", .double).notNull()
                t.column("duration", .double).notNull()
                t.column("audio_data", .blob).notNull()
                t.column("delivered_to_json", .text).notNull().defaults(to: "[]")
                t.column("played_by_json", .text).notNull().defaults(to: "[]")
            }

            // Offline queue
            try db.create(table: "offline_queue", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("ride_id", .text).notNull()
                t.column("room_id", .text)
                t.column("type", .text).notNull()
                t.column("priority", .integer).notNull()
                t.column("payload_json", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("expires_at", .double).notNull()
                t.column("ttl", .integer).notNull().defaults(to: 3)
                t.column("retry_count", .integer).notNull().defaults(to: 0)
                t.column("max_retries", .integer).notNull().defaults(to: 10)
                t.column("persist_until_ack", .boolean).notNull().defaults(to: false)
                t.column("last_error", .text)
                t.column("last_retry_at", .double)
            }

            // Mesh dedup
            try db.create(table: "mesh_dedup", ifNotExists: true) { t in
                t.column("message_id", .text).primaryKey()
                t.column("received_at", .double).notNull()
            }

            // Ride summaries
            try db.create(table: "ride_summaries", ifNotExists: true) { t in
                t.column("ride_id", .text).primaryKey()
                t.column("ride_name", .text).notNull()
                t.column("started_at", .double).notNull()
                t.column("finished_at", .double).notNull()
                t.column("total_distance", .double)
                t.column("total_duration", .double)
                t.column("max_altitude", .double)
                t.column("avg_speed", .double)
                t.column("rider_count", .integer)
                t.column("stop_count", .integer)
                t.column("alert_count", .integer)
                t.column("route_id", .text)
            }

            // Create indexes
            try db.create(index: "idx_queue_fetch",
                          on: "offline_queue",
                          columns: ["persist_until_ack", "priority", "created_at"],
                          ifNotExists: true)
            try db.create(index: "idx_queue_expiry",
                          on: "offline_queue",
                          columns: ["expires_at"],
                          ifNotExists: true)
            try db.create(index: "idx_dedup_received",
                          on: "mesh_dedup",
                          columns: ["received_at"],
                          ifNotExists: true)
        }
    }

    // MARK: - Rider Profile

    func saveProfile(_ profile: RiderProfile) {
        let key = "riderProfile"
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(profile.id, forKey: "riderProfileId")
            UserDefaults.standard.set(profile.name, forKey: "riderProfileName")
        }
    }

    func loadProfile() -> RiderProfile? {
        let key = "riderProfile"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RiderProfile.self, from: data)
    }

    func profileExists() -> Bool {
        UserDefaults.standard.data(forKey: "riderProfile") != nil
    }

    // MARK: - Rides

    func saveRide(_ ride: Ride) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO rides (id, name, leader_id, leader_name, status, created_at, finished_at, current_route_id, current_route_name)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    ride.id, ride.name, ride.leaderId, ride.leaderName,
                    ride.status.rawValue, ride.createdAt.timeIntervalSinceReferenceDate,
                    ride.finishedAt?.timeIntervalSinceReferenceDate,
                    ride.currentRouteId, ride.currentRouteName
                ]
            )
        }
    }

    func loadActiveRide() -> Ride? {
        try? dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM rides WHERE status = 'active' LIMIT 1")
        }.map { row in
            Ride(
                id: row["id"],
                name: row["name"],
                leaderId: row["leader_id"],
                leaderName: row["leader_name"]
            )
        }
    }

    func updateRideStatus(_ rideId: String, status: RideStatus) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE rides SET status = ?, finished_at = ? WHERE id = ?",
                arguments: [
                    status.rawValue,
                    status == .finished ? Date().timeIntervalSinceReferenceDate : nil,
                    rideId
                ]
            )
        }
    }

    // MARK: - Routes

    func saveRoute(_ route: Route) throws {
        let waypointsJSON = (try? JSONEncoder().encode(route.waypoints)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[]"

        let trackJSON = route.simplifiedTrack.flatMap {
            try? JSONEncoder().encode($0)
        }.flatMap { String(data: $0, encoding: .utf8) }

        let tagsJSON = (try? JSONEncoder().encode(route.tags)).flatMap {
            String(data: $0, encoding: .utf8)
        }

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO routes (id, name, created_by, created_at, source, waypoints_json, simplified_track_json, total_distance, estimated_duration, elevation_gain, tags)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    route.id, route.name, route.createdBy,
                    route.createdAt.timeIntervalSinceReferenceDate,
                    route.source.rawValue, waypointsJSON,
                    trackJSON, route.totalDistance,
                    route.estimatedDuration, route.elevationGain,
                    tagsJSON
                ]
            )
        }
    }

    func loadAllRoutes() -> [Route] {
        (try? dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM routes ORDER BY created_at DESC")
        })?.compactMap { row in
            guard let id: String = row["id"],
                  let name: String = row["name"],
                  let createdBy: String = row["created_by"],
                  let sourceRaw: String = row["source"],
                  let waypointsJSON: String = row["waypoints_json"]
            else { return nil }

            let waypoints = (try? JSONDecoder().decode([RouteWaypoint].self, from: Data(waypointsJSON.utf8))) ?? []

            var route = Route(
                id: id,
                name: name,
                createdBy: createdBy,
                source: RouteSource(rawValue: sourceRaw) ?? .drawn,
                waypoints: waypoints
            )
            route.totalDistance = row["total_distance"]
            route.estimatedDuration = row["estimated_duration"]
            route.elevationGain = row["elevation_gain"]

            if let tagsJSON: String = row["tags"],
               let tags = try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8)) {
                route.tags = tags
            }

            return route
        } ?? []
    }

    // MARK: - Rooms

    func saveRoom(_ room: Room) throws {
        let membersJSON = (try? JSONEncoder().encode(room.members)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[]"

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO rooms (id, ride_id, name, created_by, creator_name, created_at, type, is_private, members_json, is_active)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    room.id, room.rideId, room.name, room.createdBy,
                    room.creatorName, room.createdAt.timeIntervalSinceReferenceDate,
                    room.type.rawValue, room.isPrivate, membersJSON, room.isActive
                ]
            )
        }
    }

    func loadRooms(for rideId: String) -> [Room] {
        (try? dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM rooms WHERE ride_id = ? AND is_active = 1", arguments: [rideId])
        })?.compactMap { row in
            guard let id: String = row["id"],
                  let rideId: String = row["ride_id"],
                  let name: String = row["name"],
                  let createdBy: String = row["created_by"],
                  let creatorName: String = row["creator_name"],
                  let typeRaw: String = row["type"],
                  let isPrivate: Bool = row["is_private"],
                  let membersJSON: String = row["members_json"],
                  let isActive: Bool = row["is_active"]
            else { return nil }

            let members = (try? JSONDecoder().decode([String].self, from: Data(membersJSON.utf8))) ?? []

            return Room(
                id: id,
                rideId: rideId,
                name: name,
                createdBy: createdBy,
                creatorName: creatorName,
                type: RoomType(rawValue: typeRaw) ?? .messaging,
                isPrivate: isPrivate,
                members: members,
                isActive: isActive
            )
        } ?? []
    }

    // MARK: - Voice Messages

    func saveVoiceMessage(_ message: VoiceMessage) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO voice_messages (id, room_id, ride_id, from_rider_id, from_rider_name, sent_at, duration, audio_data, delivered_to_json, played_by_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    message.id, message.roomId, message.rideId,
                    message.fromRiderId, message.fromRiderName,
                    message.sentAt.timeIntervalSinceReferenceDate,
                    message.duration, message.audioData,
                    String(data: (try? JSONEncoder().encode(message.deliveredTo)) ?? Data(), encoding: .utf8) ?? "[]",
                    String(data: (try? JSONEncoder().encode(message.playedBy)) ?? Data(), encoding: .utf8) ?? "[]"
                ]
            )
        }
    }

    func loadVoiceMessages(for roomId: String) -> [VoiceMessage] {
        (try? dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM voice_messages WHERE room_id = ? ORDER BY sent_at ASC", arguments: [roomId])
        })?.compactMap { row in
            guard let id: String = row["id"],
                  let roomId: String = row["room_id"],
                  let rideId: String = row["ride_id"],
                  let fromRiderId: String = row["from_rider_id"],
                  let fromRiderName: String = row["from_rider_name"],
                  let audioData: Data = row["audio_data"],
                  let duration: Double = row["duration"],
                  let sentAt: Double = row["sent_at"],
                  let deliveredJSON: String = row["delivered_to_json"],
                  let playedJSON: String = row["played_by_json"]
            else { return nil }

            let deliveredTo = (try? JSONDecoder().decode([String].self, from: Data(deliveredJSON.utf8))) ?? []
            let playedBy = (try? JSONDecoder().decode([String].self, from: Data(playedJSON.utf8))) ?? []

            return VoiceMessage(
                id: id,
                roomId: roomId,
                rideId: rideId,
                fromRiderId: fromRiderId,
                fromRiderName: fromRiderName,
                sentAt: Date(timeIntervalSinceReferenceDate: sentAt),
                duration: duration,
                audioData: audioData,
                deliveredTo: deliveredTo,
                playedBy: playedBy
            )
        } ?? []
    }

    // MARK: - Offline Queue

    func enqueue(_ payload: MeshPayload) throws {
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"
        let expiresAt: TimeInterval

        switch payload.priority {
        case .critical: expiresAt = Date().timeIntervalSinceReferenceDate + 3600  // 1h
        case .high:     expiresAt = Date().timeIntervalSinceReferenceDate + 1800  // 30min
        case .normal:   expiresAt = Date().timeIntervalSinceReferenceDate + 600    // 10min
        case .low:      expiresAt = Date().timeIntervalSinceReferenceDate + 300    // 5min
        }

        try dbQueue.write { db in
            // Enforce max queue size (1000)
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM offline_queue") ?? 0
            if count > 1000 {
                // Remove 100 oldest low-priority messages
                try db.execute(
                    sql: "DELETE FROM offline_queue WHERE id IN (SELECT id FROM offline_queue ORDER BY priority DESC, created_at ASC LIMIT 100)"
                )
            }

            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO offline_queue (id, ride_id, room_id, type, priority, payload_json, created_at, expires_at, ttl, retry_count, max_retries, persist_until_ack)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    payload.id, payload.rideId, payload.roomId,
                    payload.type.rawValue, payload.priority.rawValue, json,
                    payload.timestamp.timeIntervalSinceReferenceDate,
                    expiresAt, payload.ttl, 0, 10,
                    payload.priority == .critical
                ]
            )
        }
    }

    func drainQueue(limit: Int = 30) -> [MeshPayload] {
        let payloads: [MeshPayload] = (try? dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT payload_json FROM offline_queue
                WHERE expires_at > ?
                ORDER BY persist_until_ack DESC, priority ASC, created_at ASC
                LIMIT ?
            """, arguments: [Date().timeIntervalSinceReferenceDate, limit])
        })?.compactMap { row in
            guard let json: String = row["payload_json"],
                  let data = json.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(MeshPayload.self, from: data)
            else { return nil }
            return payload
        } ?? []

        // Remove drained messages
        let drainedIds = payloads.map { $0.id }
        if !drainedIds.isEmpty {
            try? dbQueue.write { db in
                for id in drainedIds {
                    try db.execute(sql: "DELETE FROM offline_queue WHERE id = ?", arguments: [id])
                }
            }
        }

        return payloads
    }

    // MARK: - Mesh Dedup

    func hasMeshMessage(_ id: String) -> Bool {
        (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mesh_dedup WHERE message_id = ?", arguments: [id])
        }) ?? 0 > 0
    }

    func insertMeshDedup(_ id: String) {
        try? dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO mesh_dedup (message_id, received_at) VALUES (?, ?)",
                arguments: [id, Date().timeIntervalSinceReferenceDate]
            )
        }
        // Cleanup old entries periodically
        cleanupMeshDedup()
    }

    private func cleanupMeshDedup() {
        let cutoff = Date().timeIntervalSinceReferenceDate - 300 // 5 min
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM mesh_dedup WHERE received_at < ?", arguments: [cutoff])
        }
    }

    // MARK: - Ride Summaries

    func saveRideSummary(_ summary: RideSummary) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO ride_summaries (ride_id, ride_name, started_at, finished_at, total_distance, total_duration, max_altitude, avg_speed, rider_count, stop_count, alert_count, route_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    summary.rideId, summary.rideName,
                    summary.startedAt.timeIntervalSinceReferenceDate,
                    summary.finishedAt.timeIntervalSinceReferenceDate,
                    summary.totalDistance, summary.totalDuration,
                    summary.maxAltitude, summary.avgSpeed,
                    summary.riderCount, summary.stopCount,
                    summary.alertCount, summary.routeId
                ]
            )
        }
    }

    func loadAllSummaries() -> [RideSummary] {
        (try? dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM ride_summaries ORDER BY finished_at DESC")
        })?.compactMap { row in
            guard let rideId: String = row["ride_id"],
                  let rideName: String = row["ride_name"],
                  let startedAt: Double = row["started_at"],
                  let finishedAt: Double = row["finished_at"]
            else { return nil }

            return RideSummary(
                rideId: rideId,
                rideName: rideName,
                startedAt: Date(timeIntervalSinceReferenceDate: startedAt),
                finishedAt: Date(timeIntervalSinceReferenceDate: finishedAt),
                totalDistance: row["total_distance"],
                totalDuration: row["total_duration"],
                maxAltitude: row["max_altitude"],
                avgSpeed: row["avg_speed"],
                riderCount: row["rider_count"] ?? 0,
                stopCount: row["stop_count"] ?? 0,
                alertCount: row["alert_count"] ?? 0,
                routeId: row["route_id"]
            )
        } ?? []
    }
}
