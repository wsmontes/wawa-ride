import Foundation
import CoreLocation
import Turf

/// Checks if riders are within a corridor around the route polyline.
///
/// Uses Turf-Swift's `closestCoordinate(to:)` which computes the nearest
/// point on a LineString to a given coordinate, along with the distance.
///
/// Reference: https://github.com/mapbox/turf-swift (ISC license, 268 stars)
/// API docs: LineString.closestCoordinate(to:) returns IndexedCoordinate
///
/// Algorithm (O(n) per call where n = route segments):
/// 1. For each segment [A, B] in the polyline:
///    - Compute perpendicular projection of rider onto line(A,B)
///    - If projection falls within segment, use perpendicular distance
///    - Otherwise use distance to nearest endpoint
/// 2. Return minimum distance found across all segments
///
/// Performance: At 1 Hz GPS with 1000-point route = ~1000 haversine calcs/sec.
/// Totally fine on modern hardware. For longer routes, pre-simplify with
/// `lineString.simplified(tolerance: 10)` to reduce point count.
///
/// Usage in Wawa Ride:
/// - Check on each GPS update if rider is within corridor
/// - If outside → trigger "rider off route" alert to group
/// - Leader's route becomes the reference polyline
public struct RouteCorridor {
    private let route: LineString
    private let width: LocationDistance  // meters

    /// - Parameters:
    ///   - coordinates: The route polyline (from GPX import or Valhalla response)
    ///   - width: Corridor half-width in meters (default 100m for motorcycle groups)
    public init(coordinates: [CLLocationCoordinate2D], width: LocationDistance = 100) {
        self.route = LineString(coordinates)
        self.width = width
    }

    /// Returns distance from rider to the closest point on the route (meters).
    /// Returns nil if route is empty.
    public func distanceToRoute(_ location: CLLocationCoordinate2D) -> Double? {
        guard let closest = route.closestCoordinate(to: location) else { return nil }
        return location.distance(to: closest.coordinate)
    }

    /// Returns true if rider is within corridor width of the route.
    public func isWithinCorridor(_ location: CLLocationCoordinate2D) -> Bool {
        guard let distance = distanceToRoute(location) else { return true }
        return distance <= width
    }
}
