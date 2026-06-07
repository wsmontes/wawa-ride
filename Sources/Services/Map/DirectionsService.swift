import Foundation
import MapKit

// MARK: - Directions Service

/// Route calculation using MKDirections.
/// Calculates routes along real roads (not straight lines).
/// Supports multiple waypoints, alternate routes, and ETA.

@MainActor
final class DirectionsService: ObservableObject {
    static let shared = DirectionsService()

    @Published var activeRoutes: [MKRoute] = []
    @Published var selectedRouteIndex = 0
    @Published var isLoading = false

    var selectedRoute: MKRoute? {
        guard selectedRouteIndex < activeRoutes.count else { return nil }
        return activeRoutes[selectedRouteIndex]
    }

    private init() {}

    // MARK: - Route Calculation

    func calculateRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType = .automobile,
        alternateRoutes: Bool = false
    ) async throws -> [MKRoute] {
        isLoading = true
        defer { isLoading = false }

        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation() // fallback, overridden below
        request.source = mapItem(for: source)
        request.destination = mapItem(for: destination)
        request.transportType = transportType
        request.requestsAlternateRoutes = alternateRoutes

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        activeRoutes = response.routes
        selectedRouteIndex = 0
        return response.routes
    }

    /// Calculate route through multiple waypoints.
    /// Returns route segments for each pair of consecutive waypoints.
    func calculateRouteWithWaypoints(
        waypoints: [CLLocationCoordinate2D],
        transportType: MKDirectionsTransportType = .automobile,
        alternateRoutes: Bool = false
    ) async throws -> [MKRoute] {
        guard waypoints.count >= 2 else { return [] }

        var allRoutes: [MKRoute] = []

        for i in 0..<(waypoints.count - 1) {
            let routes = try await calculateRoute(
                from: waypoints[i],
                to: waypoints[i + 1],
                transportType: transportType,
                alternateRoutes: i == 0 ? alternateRoutes : false
            )
            allRoutes.append(contentsOf: routes)
        }

        activeRoutes = allRoutes
        selectedRouteIndex = 0
        return allRoutes
    }

    /// Calculate route to follow a leader's position.
    func calculateRouteToLeader(
        from riderLocation: CLLocationCoordinate2D,
        to leaderLocation: CLLocationCoordinate2D
    ) async throws -> [MKRoute] {
        try await calculateRoute(
            from: riderLocation,
            to: leaderLocation,
            alternateRoutes: false
        )
    }

    // MARK: - ETA

    func calculateETA(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType = .automobile
    ) async throws -> MKDirections.ETAResponse {
        let request = MKDirections.Request()
        request.source = mapItem(for: source)
        request.destination = mapItem(for: destination)
        request.transportType = transportType

        let directions = MKDirections(request: request)
        return try await directions.calculateETA()
    }

    // MARK: - Helpers

    private func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: coordinate)
        return MKMapItem(placemark: placemark)
    }

    // MARK: - Selection

    func selectRoute(at index: Int) {
        guard index < activeRoutes.count else { return }
        selectedRouteIndex = index
    }

    func clearRoutes() {
        activeRoutes = []
        selectedRouteIndex = 0
    }
}

// MARK: - MKPolyline + Coordinate Extraction

extension MKPolyline {
    func coordinates() -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }

    func combined(with other: MKPolyline) -> MKPolyline {
        let selfPoints = self.coordinates()
        let otherPoints = other.coordinates()
        let combined = selfPoints + otherPoints.dropFirst()
        return MKPolyline(coordinates: combined, count: combined.count)
    }
}
