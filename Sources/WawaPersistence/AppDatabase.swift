import Foundation
import GRDB

/// GRDB-based persistence layer for offline queue, ride history, and waypoints.
///
/// Why GRDB over Core Data / Realm / YapDatabase?
/// - GRDB: 8.5k stars, MIT, Swift 6 native, actively maintained (Jun 2026)
/// - Core Data: No CRDT, no reactive queries without wrapper, verbose API
/// - Realm: Heavy runtime, sync requires paid cloud service
/// - YapDatabase: Dead since 2020, ObjC-only, no Swift Concurrency support
///
/// Reference: https://github.com/groue/GRDB.swift
/// Documentation: https://swiftpackageindex.com/groue/GRDB.swift/documentation
///
/// Key patterns used:
/// - **DatabasePool** (WAL mode): one writer + concurrent readers, never blocks UI
///   Reference: GRDB docs "Concurrency" section
/// - **ValueObservation**: reactive queries that fire on relevant table changes
///   (not used yet in MVP but ready for phase 2 UI bindings)
/// - **Migrations**: schema versioning ensures safe upgrades without data loss
///
/// Offline queue pattern (inspired by OwnTracks):
/// - GPS positions and mesh packets are enqueued when no transport available
/// - Background task or reconnection triggers dequeue and send
/// - Each pending packet has retryCount for exponential backoff
/// Reference (OwnTracks queue): https://github.com/owntracks/ios
///
/// See also: Berty's approach using OrbitDB for persistent event logs
/// Reference: https://github.com/berty/berty — go/orbitdb package
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
            // Ride history table
            try db.create(table: "ride") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("isLeader", .boolean).notNull().defaults(to: false)
            }
            // Offline packet queue (store-and-forward pattern)
            // Reference: BitChat's smart queuing approach
            try db.create(table: "pendingPacket") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("data", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("retryCount", .integer).notNull().defaults(to: 0)
            }
            // Waypoints shared within a ride group
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

    // MARK: - Offline Queue (store-and-forward)

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

// MARK: - Record Models (GRDB PersistableRecord + FetchableRecord)

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
