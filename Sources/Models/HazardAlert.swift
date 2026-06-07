import Foundation
import CoreLocation

// MARK: - Hazard Alert

struct HazardAlert: Codable, Identifiable {
    let id: String
    let type: HazardType
    let latitude: Double
    let longitude: Double
    let reportedBy: String
    let reportedById: String
    let createdAt: Date
    let expiresAt: Date
    var confirmedBy: [String]
    var clearedBy: [String]

    var isActive: Bool {
        !isExpired && confirmedBy.count >= clearedBy.count
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var confidence: Int {
        1 + confirmedBy.count - clearedBy.count
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: String = UUID().uuidString,
        type: HazardType,
        latitude: Double,
        longitude: Double,
        reportedBy: String,
        reportedById: String
    ) {
        self.id = id
        self.type = type
        self.latitude = latitude
        self.longitude = longitude
        self.reportedBy = reportedBy
        self.reportedById = reportedById
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(type.ttlMinutes * 60))
        self.confirmedBy = [reportedBy]
        self.clearedBy = []
    }
}

enum HazardType: String, Codable, CaseIterable {
    case radar
    case pothole
    case police
    case oil
    case animal
    case gravel
    case accident
    case other

    var ttlMinutes: Int {
        switch self {
        case .radar: 30
        case .pothole: 30
        case .police: 15
        case .oil: 60
        case .animal: 15
        case .gravel: 30
        case .accident: 60
        case .other: 15
        }
    }

    var displayName: String {
        switch self {
        case .radar: "Radar"
        case .pothole: "Buraco"
        case .police: "Polícia"
        case .oil: "Óleo"
        case .animal: "Animal"
        case .gravel: "Cascalho"
        case .accident: "Acidente"
        case .other: "Outro"
        }
    }

    var iconName: String {
        switch self {
        case .radar: "antenna.radiowaves.left.and.right"
        case .pothole: "circle.dotted"
        case .police: "shield"
        case .oil: "drop"
        case .animal: "pawprint"
        case .gravel: "circle.grid.3x3"
        case .accident: "exclamationmark.triangle"
        case .other: "exclamationmark.circle"
        }
    }
}
