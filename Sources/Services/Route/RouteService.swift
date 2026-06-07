import Foundation
import CoreLocation
import MapKit

// MARK: - Route Service

/// Manages route creation, recording, and import/export.
/// Route calculation is delegated to DirectionsService (MKDirections).
/// Navigation is handled by NavigationEngine.

@MainActor
final class RouteService: ObservableObject {
    static let shared = RouteService()

    @Published var isRecording = false
    @Published var currentRoute: Route?
    @Published var trackPoints: [RoutePoint] = []
    @Published var activeWaypoints: [RouteWaypoint] = []

    private init() {}

    // MARK: - Recording

    func startRecording(name: String) {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        currentRoute = Route(name: name, createdBy: myId, source: .recorded)
        trackPoints = []
        isRecording = true
    }

    func addTrackPoint(latitude: Double, longitude: Double, speed: Double, altitude: Double?) {
        guard isRecording else { return }

        let point = RoutePoint(
            latitude: latitude,
            longitude: longitude,
            order: trackPoints.count,
            timestamp: Date(),
            speed: speed,
            altitude: altitude
        )
        trackPoints.append(point)

        // Send to mesh periodically (batch every 10 points)
        if trackPoints.count % 10 == 0 {
            sendRouteBatchToMesh()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        if !trackPoints.isEmpty {
            currentRoute?.simplifiedTrack = trackPoints
            currentRoute?.totalDistance = calculateTotalDistance(trackPoints)
        }

        // Save locally
        if let route = currentRoute {
            try? LocalStore.shared.saveRoute(route)
        }

        // Send complete route via mesh
        sendFullRouteToMesh()
    }

    // MARK: - Drawn Routes (Waypoints)

    func createDrawnRoute(name: String, waypoints: [RouteWaypoint]) -> Route {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        var route = Route(name: name, createdBy: myId, source: .drawn, waypoints: waypoints)

        // Calculate approximate straight-line distance
        let distance = calculateWaypointDistance(waypoints)
        route.totalDistance = distance

        try? LocalStore.shared.saveRoute(route)
        return route
    }

    // MARK: - Import / Export

    func importGPX(from url: URL) -> Route? {
        guard let parser = GPXParser(url: url) else { return nil }
        guard parser.parse() else { return nil }

        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let waypoints = parser.waypoints.enumerated().map { index, wp in
            RouteWaypoint(
                latitude: wp.latitude,
                longitude: wp.longitude,
                order: index,
                name: wp.name,
                type: wp.name?.lowercased().contains("stop") == true ? .stop : .waypoint,
                isStop: wp.name?.lowercased().contains("stop") == true
            )
        }

        var route = Route(name: parser.routeName ?? "Rota Importada", createdBy: myId, source: .imported, waypoints: waypoints)
        route.simplifiedTrack = parser.trackPoints
        route.totalDistance = calculateTotalDistance(parser.trackPoints)

        try? LocalStore.shared.saveRoute(route)
        return route
    }

    func exportGPX(for route: Route) -> URL? {
        let gpxString = GPXExporter.export(route: route, trackPoints: trackPoints)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(route.name).gpx")
        try? gpxString.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    func shareRouteViaMesh(_ route: Route) {
        guard let payloadData = try? JSONEncoder().encode(RoutePayload(route: route)) else { return }

        let meshPayload = MeshPayload(
            type: .routeShared,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            ttl: 8,
            priority: .low,
            payload: payloadData
        )

        TransportManager.shared.send(meshPayload)
    }

    // MARK: - Active Route

    func setActiveRoute(_ route: Route) {
        currentRoute = route
        activeWaypoints = route.waypoints.sorted { $0.order < $1.order }
        trackPoints = route.simplifiedTrack ?? []
    }

    func clearActiveRoute() {
        currentRoute = nil
        activeWaypoints = []
        trackPoints = []
    }

    // MARK: - Distance Utilities

    private func calculateTotalDistance(_ points: [RoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for i in 0..<(points.count - 1) {
            let p1 = CLLocationCoordinate2D(latitude: points[i].latitude, longitude: points[i].longitude)
            let p2 = CLLocationCoordinate2D(latitude: points[i + 1].latitude, longitude: points[i + 1].longitude)
            total += p1.distance(from: p2)
        }
        return total
    }

    private func calculateWaypointDistance(_ waypoints: [RouteWaypoint]) -> Double {
        guard waypoints.count > 1 else { return 0 }
        var total: Double = 0
        let sorted = waypoints.sorted { $0.order < $1.order }
        for i in 0..<(sorted.count - 1) {
            total += sorted[i].coordinate.distance(from: sorted[i + 1].coordinate)
        }
        return total
    }

    // MARK: - Mesh Sync

    private func sendRouteBatchToMesh() {
        let lastBatch = Array(trackPoints.suffix(10))
        let payload = RouteBatchPayload(
            routeId: currentRoute?.id ?? "",
            points: lastBatch,
            batchStart: lastBatch.first?.order ?? 0,
            batchEnd: lastBatch.last?.order ?? 0
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }

        let meshPayload = MeshPayload(
            type: .routeBatch,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            ttl: 5,
            priority: .low,
            payload: data
        )

        TransportManager.shared.send(meshPayload)
    }

    private func sendFullRouteToMesh() {
        guard let route = currentRoute else { return }
        guard let data = try? JSONEncoder().encode(RoutePayload(route: route)) else { return }

        let meshPayload = MeshPayload(
            type: .routeCreated,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            ttl: 8,
            priority: .low,
            payload: data
        )

        TransportManager.shared.send(meshPayload)
    }
}

// MARK: - CLLocationCoordinate2D Distance

extension CLLocationCoordinate2D {
    func distance(from other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
