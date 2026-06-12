import Foundation
import CoreLocation
import UIKit

// MARK: - Location Service

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var currentSpeed: Double = 0       // km/h
    @Published var currentHeading: Double = 0     // degrees 0-360
    @Published var isTracking = false

    // Adaptive rate
    private var lastHeading: Double = 0
    private var updateTimer: Timer?
    private var currentInterval: TimeInterval = 3.0
    private var offRouteDistance: Double = 0

    // Callbacks
    var onLocationUpdate: ((LocationPayload) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Permission

    func requestPermission() {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
    }

    // MARK: - Tracking

    func startTracking() {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            return
        }
        isTracking = true
        // Use best accuracy for active rides, degraded for auto-presence only
        let isInRide = AppState.shared.currentRideId != nil
        manager.desiredAccuracy = isInRide ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = isInRide ? 3 : 10
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        scheduleAdaptiveUpdates()
    }

    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Adaptive Rate

    private func scheduleAdaptiveUpdates() {
        updateTimer?.invalidate()

        let interval = calculateInterval()
        currentInterval = interval

        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.sendLocationUpdate()
                self?.scheduleAdaptiveUpdates()
            }
        }
    }

    private func calculateInterval() -> TimeInterval {
        let speed = currentSpeed
        let headingDelta = abs(currentHeading - lastHeading)
        let batteryLevel = UIDevice.current.batteryLevel

        var interval: TimeInterval = 3.0

        if headingDelta > 10 {
            interval = 1.0
        } else if headingDelta > 5 {
            interval = 1.5
        }

        if speed > 80 {
            interval = min(interval, 2.0)
        }

        if offRouteDistance > 20 {
            interval = min(interval, 1.0)
        }

        if speed < 5 {
            interval = max(interval, 10.0)
        }

        if batteryLevel > 0 && batteryLevel < 0.2 {
            interval *= 2.0
        }

        return interval
    }

    private func sendLocationUpdate() {
        guard let location = currentLocation else { return }

        let payload = LocationPayload(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            speed: currentSpeed,
            heading: currentHeading,
            altitude: location.altitude,
            batteryLevel: UIDevice.current.batteryLevel > 0
                ? Float(UIDevice.current.batteryLevel) : nil
        )

        onLocationUpdate?(payload)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            startTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        currentSpeed = max(0, location.speed * 3.6) // m/s -> km/h
        currentHeading = location.course >= 0 ? location.course : currentHeading
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        lastHeading = currentHeading
        currentHeading = newHeading.trueHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 Location error: \(error.localizedDescription)")
    }

    // MARK: - Off-route detection

    func updateOffRouteDistance(_ distance: Double) {
        offRouteDistance = distance
    }
}
