import Foundation
import MapKit
import CoreLocation

// MARK: - Navigation Engine

/// Active route navigation using MKRoute.
/// Monitors user position against the route, detects current/next step,
/// triggers TTS announcements, and handles off-route detection with rerouting.

@MainActor
final class NavigationEngine: ObservableObject {
    static let shared = NavigationEngine()

    @Published var isNavigating = false
    @Published var isPaused = false
    @Published var currentStepIndex = 0
    @Published var activeRoute: MKRoute?
    @Published var distanceToNextStep: CLLocationDistance = 0
    @Published var remainingDistance: CLLocationDistance = 0
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var offRouteDistance: CLLocationDistance = 0
    @Published var isOffRoute = false

    // Auto-pause
    private var lowSpeedStart: Date?
    private let autoPauseThreshold: TimeInterval = 30  // seconds
    private let autoPauseSpeed: Double = 3  // km/h
    private var routePolyline: MKPolyline?
    private var stepPolylinePoints: [[CLLocationCoordinate2D]] = []
    private var lastAnnouncedStepIndex = -1
    private var offRouteCount = 0
    private let maxOffRouteCount = 3

    private init() {}

    // MARK: - Start / Stop

    func startNavigation(route: MKRoute) {
        activeRoute = route
        routePolyline = route.polyline
        currentStepIndex = 0
        lastAnnouncedStepIndex = -1
        offRouteDistance = 0
        isOffRoute = false
        offRouteCount = 0
        remainingDistance = route.distance
        estimatedTimeRemaining = route.expectedTravelTime

        // Pre-compute step polylines for faster distance checks
        stepPolylinePoints = route.steps.map { $0.polyline.coordinates() }

        isNavigating = true

        // Announce first instruction
        announceNextStep()
    }

    func pauseNavigation() {
        guard isNavigating, !isPaused else { return }
        isPaused = true
        lowSpeedStart = nil
    }

    func resumeNavigation() {
        guard isNavigating, isPaused else { return }
        isPaused = false
        lowSpeedStart = nil
    }

    func stopNavigation() {
        isNavigating = false
        isPaused = false
        activeRoute = nil
        routePolyline = nil
        stepPolylinePoints = []
        currentStepIndex = 0
        lowSpeedStart = nil
    }

    // MARK: - Position Update

    func updatePosition(_ location: CLLocation) {
        guard isNavigating, let route = activeRoute else { return }

        // Auto-pause: if speed is very low for threshold duration
        let speedKmh = location.speed * 3.6
        if speedKmh < autoPauseSpeed && !isPaused {
            if lowSpeedStart == nil { lowSpeedStart = Date() }
            if let start = lowSpeedStart, Date().timeIntervalSince(start) >= autoPauseThreshold {
                pauseNavigation()
                VoiceAssistant.shared.speak(VoiceAlert(
                    text: "Navegação pausada automaticamente.",
                    priority: .normal, dedupKey: "autopause"
                ))
            }
        } else if speedKmh >= autoPauseSpeed {
            lowSpeedStart = nil
            if isPaused {
                resumeNavigation()
                VoiceAssistant.shared.speak(VoiceAlert(
                    text: "Navegação retomada.",
                    priority: .normal, dedupKey: "autoresume"
                ))
            }
        }

        // Don't process navigation updates while paused
        guard !isPaused else { return }
        let closest = findClosestPointOnRoute(from: location.coordinate)

        // Update step index
        if closest.stepIndex != currentStepIndex && closest.stepIndex > currentStepIndex {
            currentStepIndex = closest.stepIndex
            announceNextStep()
        }

        // Off-route detection
        offRouteDistance = closest.distance
        isOffRoute = closest.distance > 50

        if isOffRoute {
            offRouteCount += 1
            if offRouteCount > maxOffRouteCount {
                // Trigger rerouting
                VoiceAssistant.shared.speak(VoiceAlert(
                    text: "Recalculando rota...",
                    priority: .high, canInterrupt: true, dedupKey: "rerouting"
                ))
                requestRerouting(from: location.coordinate)
                offRouteCount = 0
            }
        } else {
            offRouteCount = 0
        }

        // Calculate remaining distance and ETA
        if let remaining = calculateRemaining(from: closest.pointIndex) {
            remainingDistance = remaining.distance
            estimatedTimeRemaining = remaining.distance / max(location.speed, 1) // rough ETA
        }

        // Distance to next step notification
        if let nextStep = nextStep {
            distanceToNextStep = closest.distanceToNextStep
            // Announce approaching step at 200m, 100m, and at the step
            if distanceToNextStep < 200 && lastAnnouncedStepIndex != currentStepIndex + 1 {
                announceUpcomingStep(nextStep, distance: distanceToNextStep)
            }
        }
    }

    // MARK: - Closest Point Search

    private struct ClosestResult {
        let pointIndex: Int
        let stepIndex: Int
        let distance: CLLocationDistance
        let distanceToNextStep: CLLocationDistance
    }

    private func findClosestPointOnRoute(from coordinate: CLLocationCoordinate2D) -> ClosestResult {
        guard let route = activeRoute else {
            return ClosestResult(pointIndex: 0, stepIndex: 0, distance: 0, distanceToNextStep: 0)
        }

        var closestDistance = CLLocationDistanceMax
        var closestPointIndex = 0
        var closestStepIndex = 0

        for (stepIndex, step) in route.steps.enumerated() {
            let points = stepPolylinePoints[stepIndex]
            for (pointIndex, point) in points.enumerated() {
                let distance = coordinate.distance(from: point)
                if distance < closestDistance {
                    closestDistance = distance
                    closestPointIndex = pointIndex
                    closestStepIndex = stepIndex
                }
            }
        }

        // Calculate distance to next step start
        var distanceToNext = CLLocationDistanceMax
        if closestStepIndex + 1 < stepPolylinePoints.count {
            if let nextFirstPoint = stepPolylinePoints[closestStepIndex + 1].first {
                distanceToNext = coordinate.distance(from: nextFirstPoint)
            }
        }

        return ClosestResult(
            pointIndex: closestPointIndex,
            stepIndex: closestStepIndex,
            distance: closestDistance,
            distanceToNextStep: distanceToNext
        )
    }

    private var nextStep: MKRoute.Step? {
        guard let route = activeRoute else { return nil }
        let nextIndex = currentStepIndex + 1
        guard nextIndex < route.steps.count else { return nil }
        return route.steps[nextIndex]
    }

    // MARK: - Remaining Distance

    private func calculateRemaining(from pointIndex: Int) -> (distance: CLLocationDistance, point: CLLocationCoordinate2D)? {
        guard let polyline = routePolyline, pointIndex < polyline.pointCount else { return nil }

        var distance: CLLocationDistance = 0
        let coords = polyline.coordinates()

        for i in pointIndex..<(coords.count - 1) {
            distance += coords[i].distance(from: coords[i + 1])
        }

        return (distance, coords.last ?? coords[pointIndex])
    }

    // MARK: - TTS Announcements

    private func announceNextStep() {
        guard let route = activeRoute, currentStepIndex < route.steps.count else { return }
        guard currentStepIndex != lastAnnouncedStepIndex else { return }

        let step = route.steps[currentStepIndex]
        lastAnnouncedStepIndex = currentStepIndex

        // Use MKRoute.Step.instructions directly (MapKit provides pt-BR instructions)
        let text: String
        if step.distance > 0 {
            text = step.instructions
        } else {
            text = step.notice ?? step.instructions
        }

        VoiceAssistant.shared.speak(VoiceAlert(
            text: text,
            priority: .high,
            canInterrupt: true,
            dedupKey: "nav_step_\(currentStepIndex)"
        ))
    }

    private func announceUpcomingStep(_ step: MKRoute.Step, distance: CLLocationDistance) {
        let distStr: String
        if distance > 1000 {
            distStr = String(format: "%.1f km", distance / 1000)
        } else {
            distStr = "\(Int(distance)) metros"
        }

        VoiceAssistant.shared.speak(VoiceAlert(
            text: "Em \(distStr), \(step.instructions)",
            priority: .high,
            canInterrupt: true,
            dedupKey: "nav_upcoming_\(currentStepIndex + 1)"
        ))
    }

    // MARK: - Rerouting

    private func requestRerouting(from coordinate: CLLocationCoordinate2D) {
        guard let route = activeRoute else { return }

        // Get the destination (last point of current route)
        let coords = route.polyline.coordinates()
        guard let destination = coords.last else { return }

        Task {
            do {
                let routes = try await DirectionsService.shared.calculateRoute(
                    from: coordinate,
                    to: destination
                )
                if let newRoute = routes.first {
                    startNavigation(route: newRoute)
                    VoiceAssistant.shared.speak(VoiceAlert(
                        text: "Rota recalculada.",
                        priority: .normal,
                        dedupKey: "rerouted"
                    ))
                }
            } catch {
                print("🧭 Rerouting failed: \(error)")
                VoiceAssistant.shared.speak(VoiceAlert(
                    text: "Não foi possível recalcular a rota.",
                    priority: .high,
                    dedupKey: "reroute_failed"
                ))
            }
        }
    }
}

