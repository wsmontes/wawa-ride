import Foundation
import FerrostarCore
import CoreLocation

/// Wraps Valhalla routing via Ferrostar's built-in adapter.
public final class RouteService {
    private let valhallaURL: URL
    private let profile: String

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
