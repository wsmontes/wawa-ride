import Foundation
import CoreLocation

/// Battery-efficient location tracking (OwnTracks-inspired adaptive rate).
final class SmartLocationTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastBroadcast: Date = .distantPast
    private var onLocation: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func start(onLocation: @escaping (CLLocation) -> Void) {
        self.onLocation = onLocation
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        onLocation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let interval: TimeInterval = {
            guard loc.speed > 0 else { return 5.0 }
            return loc.speed > 20 ? 0.5 : (loc.speed > 5 ? 1.0 : 2.0)
        }()
        guard Date().timeIntervalSince(lastBroadcast) >= interval else { return }
        lastBroadcast = Date()
        onLocation?(loc)
    }
}
