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

    // Route (from DirectionsService)
    @Published var activeRoute: MKRoute?
    @Published var routePolyline: MKPolyline?
    @Published var alternateRoutes: [MKRoute] = []

    // Navigation (from NavigationEngine)
    @Published var isNavigating = false
    @Published var currentStepInstructions: String?
    @Published var distanceToNextStep: CLLocationDistance = 0
    @Published var remainingDistance: CLLocationDistance = 0
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var offRouteDistance: Double = 0

    // Speed & heading
    @Published var speed: Double = 0
    @Published var heading: Double = 0

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

    // MARK: - Route Display

    func setActiveRoute(_ route: MKRoute) {
        activeRoute = route
        routePolyline = route.polyline
    }

    /// Display a polyline from raw track points (used for mesh-received routes)
    func setTrackPolyline(trackPoints: [RoutePoint]) {
        guard trackPoints.count > 1 else { return }
        let coords = trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        routePolyline = MKPolyline(coordinates: coords, count: coords.count)
    }

    func setAlternateRoutes(_ routes: [MKRoute]) {
        alternateRoutes = routes
    }

    func clearRoute() {
        activeRoute = nil
        routePolyline = nil
        alternateRoutes = []
        isNavigating = false
        currentStepInstructions = nil
        distanceToNextStep = 0
        remainingDistance = 0
        estimatedTimeRemaining = 0
        offRouteDistance = 0
    }

    // MARK: - Navigation

    func startNavigation(with route: MKRoute) {
        setActiveRoute(route)
        isNavigating = true
        NavigationEngine.shared.startNavigation(route: route)
    }

    func stopNavigation() {
        isNavigating = false
        NavigationEngine.shared.stopNavigation()
    }

    func updateNavigationFromEngine() {
        let nav = NavigationEngine.shared
        currentStepInstructions = nav.activeRoute?.steps[nav.currentStepIndex].instructions
        distanceToNextStep = nav.distanceToNextStep
        remainingDistance = nav.remainingDistance
        estimatedTimeRemaining = nav.estimatedTimeRemaining
        offRouteDistance = nav.offRouteDistance
    }

    // MARK: - Location

    func updateLocation(speed: Double, heading: Double) {
        self.speed = speed
        self.heading = heading
    }

    func rider(for annotation: RiderAnnotation) -> RideParticipant? {
        participants.first { $0.riderId == annotation.riderId }
    }

    func hazard(for annotation: HazardAnnotation) -> HazardAlert? {
        alerts.first { $0.id == annotation.id }
    }

    // MARK: - Display Strings

    var statusText: String {
        if isNavigating {
            if let instructions = currentStepInstructions {
                return "\(Int(speed)) km/h • \(instructions)"
            }
            return "\(Int(speed)) km/h • \(formatDistance(remainingDistance)) restantes"
        }
        if let route = activeRoute {
            let km = route.distance / 1000
            let eta = formatDuration(route.expectedTravelTime)
            return "\(Int(speed)) km/h • \(String(format: "%.1f", km)) km • \(eta)"
        }
        return "\(Int(speed)) km/h"
    }

    var navigationStatusText: String {
        guard isNavigating else { return "" }

        if offRouteDistance > 50 {
            return "Fora da rota (\(Int(offRouteDistance))m)"
        }

        let remain = formatDistance(remainingDistance)
        let eta = formatDuration(estimatedTimeRemaining)
        return "\(remain) • \(eta)"
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

    // MARK: - Format Helpers

    private func formatDistance(_ meters: Double) -> String {
        if meters > 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)min"
        }
        return "\(minutes) min"
    }
}
