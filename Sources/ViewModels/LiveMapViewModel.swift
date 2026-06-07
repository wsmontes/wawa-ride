import SwiftUI
import MapKit

// MARK: - Live Map View Model

@MainActor
final class LiveMapViewModel: ObservableObject {
    // Riders
    @Published var participants: [RideParticipant] = []
    @Published var riderAnnotations: [RiderAnnotation] = []

    // Hazards
    @Published var alerts: [HazardAlert] = []
    @Published var hazardAnnotations: [HazardAnnotation] = []

    // Route
    @Published var routePolyline: MKPolyline?
    @Published var offRouteDistance: Double = 0
    @Published var nextTurn: TurnInfo?

    // Status
    @Published var speed: Double = 0
    @Published var heading: Double = 0
    @Published var isTrackingRoute = false

    // Connectivity
    @Published var meshState: MeshService.MeshState = .idle
    @Published var connectedCount = 0
    @Published var totalCount = 0

    // Callbacks
    var onMapLongPress: ((CLLocationCoordinate2D) -> Void)?
    var onSelectRider: ((RideParticipant) -> Void)?
    var onSelectHazard: ((HazardAlert) -> Void)?

    func updateParticipants(_ participants: [RideParticipant]) {
        self.participants = participants
        self.riderAnnotations = participants.map { RiderAnnotation(participant: $0) }
        self.connectedCount = participants.filter { $0.isConnected }.count
        self.totalCount = participants.count
    }

    func updateAlerts(_ alerts: [HazardAlert]) {
        self.alerts = alerts
        self.hazardAnnotations = alerts.filter { $0.isActive }.map { HazardAnnotation(alert: $0) }
    }

    func updateRoute(trackPoints: [RoutePoint]) {
        guard trackPoints.count > 1 else {
            routePolyline = nil
            return
        }

        let coords = trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        routePolyline = MKPolyline(coordinates: coords, count: coords.count)
        isTrackingRoute = true
    }

    func clearRoute() {
        routePolyline = nil
        isTrackingRoute = false
        offRouteDistance = 0
        nextTurn = nil
    }

    func updateLocation(speed: Double, heading: Double) {
        self.speed = speed
        self.heading = heading
    }

    // MARK: - Rider Management

    func rider(for annotation: RiderAnnotation) -> RideParticipant? {
        participants.first { $0.riderId == annotation.riderId }
    }

    func hazard(for annotation: HazardAnnotation) -> HazardAlert? {
        alerts.first { $0.id == annotation.id }
    }

    var statusText: String {
        if !isTrackingRoute {
            return "\(Int(speed)) km/h"
        }
        if let turn = nextTurn {
            return "\(Int(speed)) km/h • \(Int(turn.distance))m até \(turn.severity.lowercased()) \(turn.direction)"
        }
        if offRouteDistance > 50 {
            return "\(Int(speed)) km/h • Fora da rota (\(Int(offRouteDistance))m)"
        }
        return "\(Int(speed)) km/h • Na rota"
    }

    var connectivityIcon: String {
        switch meshState {
        case .connected: return "🟢"
        case .advertising, .browsing: return "🔵"
        case .idle: return "⚫"
        }
    }

    var titleBarText: String {
        "\(AppState.shared.currentRideName ?? "WAWA Ride")  \(connectivityIcon)\(connectedCount)"
    }
}
