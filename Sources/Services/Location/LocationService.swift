import Foundation
import CoreLocation
import os.log

/// Provides real-time GPS updates for the local rider.
/// Publishes location at configurable frequency for sharing with the group.
final class LocationService: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - Published

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isUpdating = false

    // MARK: - Properties

    private let manager = CLLocationManager()
    private let log = Logger(subsystem: "com.wawaride", category: "Location")
    private var updateContinuation: AsyncStream<CLLocation>.Continuation?

    /// Async stream yielding location updates at the desired frequency.
    private(set) lazy var locationUpdates = AsyncStream<CLLocation> { continuation in
        self.updateContinuation = continuation
    }

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Public API

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        isUpdating = true
        log.info("Location updates started")
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        isUpdating = false
        log.info("Location updates stopped")
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        log.info("Auth status: \(manager.authorizationStatus.rawValue)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest
        updateContinuation?.yield(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("Location error: \(error.localizedDescription)")
    }
}
