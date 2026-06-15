import Foundation
import CoreLocation
import Turf

/// Checks if riders are within a corridor around the route.
public struct RouteCorridor {
    private let route: LineString
    private let width: LocationDistance

    /// - Parameters:
    ///   - coordinates: The route polyline
    ///   - width: Corridor width in meters (default 100m)
    public init(coordinates: [CLLocationCoordinate2D], width: LocationDistance = 100) {
        self.route = LineString(coordinates)
        self.width = width
    }

    /// Returns distance from rider to route (meters). Nil if route is empty.
    public func distanceToRoute(_ location: CLLocationCoordinate2D) -> Double? {
        guard let closest = route.closestCoordinate(to: location) else { return nil }
        return location.distance(to: closest.coordinate)
    }

    /// Returns true if rider is within corridor.
    public func isWithinCorridor(_ location: CLLocationCoordinate2D) -> Bool {
        guard let distance = distanceToRoute(location) else { return true }
        return distance <= width
    }
}
