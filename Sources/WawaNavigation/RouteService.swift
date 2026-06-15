import Foundation
import FerrostarCore
import CoreLocation

/// Wraps Valhalla routing via Ferrostar's built-in WellKnownRouteProvider.
///
/// Architecture: iOS app → HTTP POST → Valhalla server → OSRM JSON response → Ferrostar
///
/// Why Ferrostar + Valhalla (not GraphHopper, OSRM, or Apple Directions)?
/// - Ferrostar: BSD-2, 600+ stars, Rust core + Swift bindings, has built-in Valhalla adapter
/// - Valhalla: MIT, 8k stars, motorcycle costing (beta), map matching (Meili), offline tiles
/// - GraphHopper: Apache-2, Java, can't embed in iOS (server only)
/// - OSRM: BSD, C++, no motorcycle profile, harder to customize costing
/// - Apple Directions: proprietary, no offline, no motorcycle, no customization
///
/// Ferrostar reference: https://github.com/stadiamaps/ferrostar
/// Ferrostar iOS docs: https://stadiamaps.github.io/ferrostar/
///
/// Valhalla reference: https://github.com/valhalla/valhalla
/// Motorcycle costing: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/#motorcycle-costing-options
///
/// StepAdvanceCondition configured for off-road/group riding:
/// - Relaxed distances (50m entry, 30m exit) for GPS inaccuracy on trails
/// - 200m distance-from-step fallback for when rider takes alternate path
/// - minimumHorizontalAccuracy: 50m (accept less accurate GPS in forests/valleys)
///
/// Route deviation threshold: 100m (vs typical 25m for road driving)
/// This avoids false "off route" alerts on unpaved/unmapped roads.
///
/// Reference for StepAdvanceCondition patterns:
/// https://stadiamaps.github.io/ferrostar/guide/ios/customization/step-advance.html
public final class RouteService {
    private let valhallaURL: URL
    private let profile: String

    /// Initialize with Valhalla server URL.
    /// - Parameters:
    ///   - baseURL: Valhalla HTTP endpoint (e.g., "http://localhost:8002")
    ///     For production, use Docker: `ghcr.io/gis-ops/docker-valhalla/valhalla:latest`
    ///   - profile: Valhalla costing model. Options: "auto", "bicycle", "motorcycle", "pedestrian"
    ///     Reference: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/#costing-models
    public init(baseURL: URL, profile: String = "motorcycle") {
        self.valhallaURL = baseURL.appendingPathComponent("route")
        self.profile = profile
    }

    /// Create FerrostarCore configured for group motorcycle riding.
    public func createNavigationCore(locationProvider: LocationProviding) throws -> FerrostarCore {
        let config = SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(100.0),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
                distanceToEndOfStep: 50,
                distanceAfterEndOfStep: 30,
                minimumHorizontalAccuracy: 50
            ),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(
                distance: 15, minimumHorizontalAccuracy: 25
            ),
            routeDeviationTracking: .staticThreshold(
                minimumHorizontalAccuracy: 20,
                maxAcceptableDeviation: 100.0
            ),
            snappedLocationCourseFiltering: .snapToRoute
        )
        return try FerrostarCore(
            wellKnownRouteProvider: .valhalla(
                endpointUrl: valhallaURL.absoluteString,
                profile: profile,
                optionsJson: costingJSON()
            ),
            locationProvider: locationProvider,
            navigationControllerConfig: config
        )
    }

    /// Valhalla costing options for motorcycle group riding.
    /// - use_highways: 0.3 (prefer scenic/secondary roads)
    /// - use_trails: 0.7 (adventure riding on unpaved/tracks)
    /// Reference: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/#motorcycle-costing-options
    private func costingJSON() -> String? {
        let opts: [String: Any] = [
            "costing_options": [profile: ["use_highways": 0.3, "use_trails": 0.7]],
            "directions_options": ["units": "km", "language": "pt-BR"],
            "banner_instructions": true,
            "voice_instructions": true
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: opts) else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
