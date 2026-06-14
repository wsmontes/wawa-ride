import Foundation

/// A group of riders — formed when one rider creates a "passeio" and others join.
struct RideGroup: Codable, Identifiable {
    let id: UUID
    var name: String
    var ownerID: String
    var memberIDs: [String]
    var createdAt: Date

    static func create(name: String, ownerID: String) -> RideGroup {
        RideGroup(
            id: UUID(),
            name: name,
            ownerID: ownerID,
            memberIDs: [ownerID],
            createdAt: Date()
        )
    }
}
