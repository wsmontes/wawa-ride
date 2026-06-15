import Foundation
import CoreLocation

/// Valhalla trace_route (Meili) — snaps noisy GPS to road network.
public final class MapMatchingService {
    private let traceURL: URL

    public init(baseURL: URL) {
        self.traceURL = baseURL.appendingPathComponent("trace_route")
    }

    public func matchTrace(coordinates: [CLLocationCoordinate2D], costing: String = "motorcycle") async throws -> MatchedRoute {
        let shape = coordinates.map { ["lat": $0.latitude, "lon": $0.longitude] }
        let body: [String: Any] = [
            "shape": shape, "costing": costing,
            "shape_match": "map_snap", "format": "osrm",
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
    public let distance: Double
    public let duration: Double
}

private struct OSRMResponse: Decodable { let routes: [OSRMRoute] }
private struct OSRMRoute: Decodable { let geometry: String; let distance: Double; let duration: Double }
private enum MapMatchError: Error { case noMatch }
