import Foundation

// MARK: - Rider Profile

struct RiderProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var bikeModel: String?
    var photoData: Data?
    var defaultRole: RideRole
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        bikeModel: String? = nil,
        photoData: Data? = nil,
        defaultRole: RideRole = .rider
    ) {
        self.id = id
        self.name = name
        self.bikeModel = bikeModel
        self.photoData = photoData
        self.defaultRole = defaultRole
        self.createdAt = Date()
    }

    var initials: String {
        name.components(separatedBy: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
            .uppercased()
    }
}

enum RideRole: String, Codable, CaseIterable {
    case leader
    case rider
    case sweeper

    var displayName: String {
        switch self {
        case .leader: "Líder"
        case .rider: "Rider"
        case .sweeper: "Varredor"
        }
    }
}
