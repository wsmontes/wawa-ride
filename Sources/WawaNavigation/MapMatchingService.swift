import Foundation
import CoreLocation

/// Valhalla's trace_route API (Meili) — snaps noisy GPS points to road network.
///
/// Use case for Wawa Ride: reconstruct a clean leader trail from mesh location
/// updates (which may be noisy, out-of-order, or have gaps due to BLE range).
///
/// Reference: https://valhalla.github.io/valhalla/api/map-matching/api-reference/
///
/// API endpoint: POST /trace_route
/// Key parameters:
/// - shape_match: "map_snap" (force snap even if some points are off-road)
/// - format: "osrm" (response compatible with Ferrostar's route parser)
/// - costing: matches the ride profile (motorcycle/bicycle)
///
/// The response includes a full route with maneuvers, making it possible to
/// generate turn-by-turn instructions from a recorded GPS trace.
///
/// Polyline6 decoding: Valhalla uses 6-digit precision (degrees × 1e6),
/// unlike Google's polyline5 (degrees × 1e5). This gives ~11cm precision.
/// Reference: https://valhalla.github.io/valhalla/decoding/
public final class MapMatchingService {
    private let traceURL: URL

    /// Initialize with Valhalla server base URL.
    /// trace_route is at: {baseURL}/trace_route
    public init(baseURL: URL) {
        self.traceURL = baseURL.appendingPathComponent("trace_route")
    }

    /// Snap a sequence of GPS coordinates to the road network.
    /// Returns a clean geometry with road-matched positions.
    ///
    /// - Parameters:
    ///   - coordinates: Raw GPS points (from mesh location updates)
    ///   - costing: Valhalla profile ("motorcycle", "bicycle", "auto", "pedestrian")
    /// - Returns: MatchedRoute with clean geometry, total distance, and duration
    public func matchTrace(coordinates: [CLLocationCoordinate2D], costing: String = "motorcycle") async throws -> MatchedRoute {
        let shape = coordinates.map { ["lat": $0.latitude, "lon": $0.longitude] }
        let body: [String: Any] = [
            "shape": shape,
            "costing": costing,
            "shape_match": "map_snap",  // Force snap (vs "walk_or_snap" which may give up)
            "format": "osrm",           // OSRM format for Ferrostar compatibility
            "directions_options": ["units": "km"]
        ]
        var req = URLRequest(url: traceURL)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard let route = resp.routes.first else { throw MapMatchError.noMatch }
        return MatchedRoute(geometry: decodePolyline6(route.geometry), distance: route.distance, duration: route.duration)
    }

    /// Decode Valhalla's polyline6 format (6-digit precision).
    /// Reference: https://valhalla.github.io/valhalla/decoding/
    /// Standard polyline algorithm but with divisor 1e6 instead of 1e5.
    private func decodePolyline6(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        var lat = 0, lng = 0
        var i = encoded.startIndex
        func nextValue() -> Int {
            var shift = 0, result = 0, byte: Int
            repeat {
                byte = Int(encoded[i].asciiValue! - 63); i = encoded.index(after: i)
                result |= (byte & 0x1F) << shift; shift += 5
            } while byte >= 0x20
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }
        while i < encoded.endIndex {
            lat += nextValue(); lng += nextValue()
            coords.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e6, longitude: Double(lng) / 1e6))
        }
        return coords
    }
}

public struct MatchedRoute: Sendable {
    public let geometry: [CLLocationCoordinate2D]
    public let distance: Double  // meters
    public let duration: Double  // seconds
}

private struct OSRMResponse: Decodable { let routes: [OSRMRoute] }
private struct OSRMRoute: Decodable { let geometry: String; let distance: Double; let duration: Double }
private enum MapMatchError: Error { case noMatch }
