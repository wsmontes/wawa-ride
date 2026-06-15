import Foundation
import GRDB

/// GRDB database manager for offline queue, ride history, and waypoints.
public final class AppDatabase: Sendable {
    private let dbPool: DatabasePool

    public init(path: String? = nil) throws {
        let dbPath = path ?? AppDatabase.defaultPath()
        dbPool = try DatabasePool(path: dbPath)
        try migrator.migrate(dbPool)
    }

    private static func defaultPath() -> String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("wawaride.sqlite").path
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "ride") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("isLeader", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "pendingPacket") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("data", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("retryCount", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "waypoint") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("rideId", .integer).references("ride")
                t.column("lat", .double).notNull()
                t.column("lon", .double).notNull()
                t.column("name", .text)
                t.column("createdAt", .datetime).notNull()
            }
        }
        return m
    }

    // MARK: - Offline Queue

    public func enqueuePendingPacket(_ data: Data) throws {
        try dbPool.write { db in
            try PendingPacket(data: data, createdAt: Date(), retryCount: 0).insert(db)
        }
    }

    public func dequeuePendingPackets(limit: Int = 20) throws -> [PendingPacket] {
        try dbPool.read { db in
            try PendingPacket.order(Column("createdAt")).limit(limit).fetchAll(db)
        }
    }

    public func removePendingPacket(id: Int64) throws {
        try dbPool.write { db in
            _ = try PendingPacket.deleteOne(db, id: id)
        }
    }

    // MARK: - Ride History

    public func startRide(isLeader: Bool) throws -> Ride {
        try dbPool.write { db in
            var ride = Ride(startedAt: Date(), endedAt: nil, isLeader: isLeader)
            try ride.insert(db)
            return ride
        }
    }

    public func endRide(_ ride: inout Ride) throws {
        ride.endedAt = Date()
        try dbPool.write { db in try ride.update(db) }
    }

    public func recentRides(limit: Int = 20) throws -> [Ride] {
        try dbPool.read { db in
            try Ride.order(Column("startedAt").desc).limit(limit).fetchAll(db)
        }
    }
}

// MARK: - Models

public struct PendingPacket: Codable, FetchableRecord, PersistableRecord, Identifiable {
    public var id: Int64?
    public var data: Data
    public var createdAt: Date
    public var retryCount: Int

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Ride: Codable, FetchableRecord, PersistableRecord, Identifiable {
    public var id: Int64?
    public var startedAt: Date
    public var endedAt: Date?
    public var isLeader: Bool

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct Waypoint: Codable, FetchableRecord, PersistableRecord, Identifiable {
    public var id: Int64?
    public var rideId: Int64?
    public var lat: Double
    public var lon: Double
    public var name: String?
    public var createdAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
