import Foundation
import CoreLocation
import os.log

final class LocationService: NSObject, ObservableObject, @unchecked Sendable {

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isUpdating = false
    @Published var error: String?

    private let manager = CLLocationManager()
    private let log = Logger(subsystem: "com.wawaride", category: "Location")

    let locationUpdates: AsyncStream<CLLocation>
    private let updateContinuation: AsyncStream<CLLocation>.Continuation

    override init() {
        (locationUpdates, updateContinuation) = AsyncStream<CLLocation>.makeStream()
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        self.manager.distanceFilter = 5
        self.manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = self.manager.authorizationStatus
        self.log.info("LocationService init — status: \(self.manager.authorizationStatus.rawValue)")
    }

    func requestPermission() {
        let status = manager.authorizationStatus
        log.info("Requesting permission — current status: \(status.rawValue)")
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        // If already authorized, just start updating
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startUpdating()
        }
    }

    func startUpdating() {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            error = "Permissao de localizacao negada. Va em Ajustes > Wawa Ride > Localizacao."
            log.warning("Location denied (status: \(status.rawValue))")
            isUpdating = false
            return
        }
        error = nil
        manager.startUpdatingLocation()
        isUpdating = true
        log.info("Location updates started (status: \(status.rawValue))")
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
        log.info("Auth changed → \(manager.authorizationStatus.rawValue)")
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            error = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest
        updateContinuation.yield(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("Location error: \(error.localizedDescription)")
        self.error = error.localizedDescription
    }
}
