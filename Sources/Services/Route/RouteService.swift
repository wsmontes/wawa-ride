import Foundation
import CoreLocation
import MapKit

// MARK: - Route Service

/// Manages route creation, recording, and navigation.
/// Modes: Record live (leader's track), Draw waypoints, Import .GPX.

@MainActor
final class RouteService: ObservableObject {
    static let shared = RouteService()

    @Published var isRecording = false
    @Published var currentRoute: Route?
    @Published var trackPoints: [RoutePoint] = []
    @Published var activeWaypoints: [RouteWaypoint] = []

    // Navigation state
    @Published var offRouteDistance: Double = 0
    @Published var nextTurn: TurnInfo?
    @Published var distanceToNextTurn: Double = 0

    // Simplification
    private let simplifier = RouteSimplifier()

    private override init() {}

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

        // Simplify track
        if !trackPoints.isEmpty {
            let simplified = simplifier.simplify(trackPoints, tolerance: 5.0)
            currentRoute?.simplifiedTrack = simplified
            currentRoute?.totalDistance = calculateTotalDistance(simplified)
        }

        // Save locally
        if let route = currentRoute {
            try? LocalStore.shared.saveRoute(route)
        }

        // Send complete route via mesh
        sendFullRouteToMesh()
    }

    // MARK: - Drawing (Waypoints)

    func createDrawnRoute(name: String, waypoints: [RouteWaypoint]) -> Route {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        var route = Route(name: name, createdBy: myId, source: .drawn, waypoints: waypoints)

        // Calculate approximate distance between waypoints
        let distance = calculateWaypointDistance(waypoints)
        route.totalDistance = distance

        try? LocalStore.shared.saveRoute(route)
        return route
    }

    // MARK: - Import

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

    // MARK: - Sharing

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
        offRouteDistance = 0
        nextTurn = nil
    }

    // MARK: - Navigation

    func updateNavigation(currentLocation: CLLocation) {
        guard !trackPoints.isEmpty else { return }

        // Find closest point on route
        guard let closest = findClosestPoint(to: currentLocation.coordinate) else { return }
        let distance = currentLocation.distance(from: CLLocation(latitude: closest.latitude, longitude: closest.longitude))

        offRouteDistance = distance
        LocationService.shared.updateOffRouteDistance(distance)

        // Find next turn
        if let turn = findNextTurn(from: closest.order) {
            nextTurn = turn
            distanceToNextTurn = calculateDistance(from: closest.order, to: turn.pointIndex)
        }
    }

    private func findClosestPoint(to coordinate: CLLocationCoordinate2D) -> RoutePoint? {
        guard !trackPoints.isEmpty else { return nil }

        var closest = trackPoints[0]
        var minDistance = Double.infinity

        for point in trackPoints {
            let pCoord = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            let d = coordinate.distance(from: pCoord)
            if d < minDistance {
                minDistance = d
                closest = point
            }
        }

        return closest
    }

    // MARK: - Turn Detection

    func findNextTurn(from currentIndex: Int) -> TurnInfo? {
        let lookAhead = 20  // points ahead
        let endIndex = min(currentIndex + lookAhead, trackPoints.count - 1)

        guard endIndex > currentIndex + 2 else { return nil }

        for i in (currentIndex + 2)..<endIndex {
            let angle = calculateTurnAngle(at: i)
            if angle > 15 {
                let direction = calculateTurnDirection(at: i)
                let severity = angle > 90 ? "Curva fechada" : angle > 45 ? "Curva acentuada" : "Curva suave"
                let distance = calculateDistance(from: currentIndex, to: i)
                return TurnInfo(
                    pointIndex: i,
                    angle: angle,
                    direction: direction,
                    severity: severity,
                    distance: distance
                )
            }
        }

        return nil
    }

    private func calculateTurnAngle(at index: Int) -> Double {
        guard index > 1, index < trackPoints.count else { return 0 }

        let p1 = trackPoints[index - 2]
        let p2 = trackPoints[index - 1]
        let p3 = trackPoints[index]

        let v1 = CGPoint(x: p2.longitude - p1.longitude, y: p2.latitude - p1.latitude)
        let v2 = CGPoint(x: p3.longitude - p2.longitude, y: p3.latitude - p2.latitude)

        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)

        guard mag1 > 0, mag2 > 0 else { return 0 }

        let cosAngle = max(-1, min(1, dot / (mag1 * mag2)))
        return acos(cosAngle) * 180 / .pi
    }

    private func calculateTurnDirection(at index: Int) -> String {
        guard index > 0, index < trackPoints.count else { return "à frente" }

        let p1 = trackPoints[index - 1]
        let p2 = trackPoints[index]

        let cross = (p2.longitude - p1.longitude) * (p2.latitude + p1.latitude)

        // Simplified: positive cross product = left turn, negative = right turn
        return cross > 0 ? "à esquerda" : "à direita"
    }

    // MARK: - Distance Calculation

    private func calculateDistance(from startIndex: Int, to endIndex: Int) -> Double {
        guard startIndex < endIndex, endIndex < trackPoints.count else { return 0 }
        var total: Double = 0
        for i in startIndex..<endIndex {
            let p1 = CLLocationCoordinate2D(latitude: trackPoints[i].latitude, longitude: trackPoints[i].longitude)
            let p2 = CLLocationCoordinate2D(latitude: trackPoints[i + 1].latitude, longitude: trackPoints[i + 1].longitude)
            total += p1.distance(from: p2)
        }
        return total
    }

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
            let p1 = CLLocationCoordinate2D(latitude: sorted[i].latitude, longitude: sorted[i].longitude)
            let p2 = CLLocationCoordinate2D(latitude: sorted[i + 1].latitude, longitude: sorted[i + 1].longitude)
            total += p1.distance(from: p2)
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

// MARK: - Turn Info

struct TurnInfo {
    let pointIndex: Int
    let angle: Double
    let direction: String
    let severity: String
    let distance: Double
}

// MARK: - Route Simplifier (Ramer-Douglas-Peucker)

final class RouteSimplifier {
    func simplify(_ points: [RoutePoint], tolerance: Double) -> [RoutePoint] {
        guard points.count > 2 else { return points }

        let coords = points.map { CGPoint(x: $0.longitude, y: $0.latitude) }

        // Convert tolerance (meters) to approximate coordinate tolerance
        // 1 degree ≈ 111,000 meters
        let coordTolerance = tolerance / 111_000.0

        let kept = rdpSimplify(coords, tolerance: coordTolerance)
        var result: [RoutePoint] = []
        var keptSet = Set(kept.map { "\($0.x),\($0.y)" })

        for point in points {
            let key = "\(point.longitude),\(point.latitude)"
            if keptSet.contains(key) {
                result.append(point)
            }
        }

        // Renumber orders
        for i in result.indices {
            var p = result[i]
            result[i] = RoutePoint(
                latitude: p.latitude, longitude: p.longitude,
                order: i, timestamp: p.timestamp,
                speed: p.speed, altitude: p.altitude
            )
        }

        return result
    }

    private func rdpSimplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var maxDistance: Double = 0
        var maxIndex = 0

        let first = points.first!
        let last = points.last!

        for i in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[i], first, last)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }

        if maxDistance > tolerance {
            let left = rdpSimplify(Array(points[0...maxIndex]), tolerance: tolerance)
            let right = rdpSimplify(Array(points[maxIndex...]), tolerance: tolerance)
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    private func perpendicularDistance(_ point: CGPoint, _ lineStart: CGPoint, _ lineEnd: CGPoint) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let mag = dx * dx + dy * dy

        guard mag > 0 else { return sqrt(pow(point.x - lineStart.x, 2) + pow(point.y - lineStart.y, 2)) }

        var t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / mag
        t = max(0, min(1, t))

        let projX = lineStart.x + t * dx
        let projY = lineStart.y + t * dy

        return sqrt(pow(point.x - projX, 2) + pow(point.y - projY, 2))
    }
}

// MARK: - CLLocationCoordinate2D Distance Extension

extension CLLocationCoordinate2D {
    func distance(from other: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: latitude, longitude: longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}
