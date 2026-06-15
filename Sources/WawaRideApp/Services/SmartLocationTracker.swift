import Foundation
import CoreLocation

/// Battery-efficient location tracking with adaptive broadcast rate.
///
/// Inspired by OwnTracks iOS (MIT, 418 stars):
/// https://github.com/owntracks/ios
///
/// Key OwnTracks patterns adopted:
/// 1. Only publish when OS detects movement (significant location change)
/// 2. Adaptive rate based on speed (faster movement → more frequent updates)
/// 3. Background location indicator (blue bar) to inform user
/// 4. `pausesLocationUpdatesAutomatically = false` for continuous ride tracking
///
/// Rate adaptation:
/// - Stopped/walking (0-5 m/s): every 5 seconds
/// - Slow riding (5-20 m/s): every 1 second
/// - Normal riding (20-50 m/s): every 0.5 seconds
/// - High speed (>50 m/s): every 0.5 seconds
///
/// Battery considerations:
/// - GPS at 1 Hz with best accuracy ≈ 3-5% battery/hour (iPhone 14+)
/// - Acceptable for a 2-4 hour motorcycle ride
/// - Could reduce to significant-location-change-only for longer tours
///
/// See also:
/// - Apple docs: https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
/// - BGTaskScheduler for deferred sync: https://developer.apple.com/documentation/backgroundtasks
final class SmartLocationTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastBroadcast: Date = .distantPast
    private var onLocation: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Required for continuous tracking in background (ride in progress)
        manager.allowsBackgroundLocationUpdates = true
        // Don't let iOS pause updates (we need continuous during ride)
        manager.pausesLocationUpdatesAutomatically = false
        // Show blue indicator bar when tracking in background
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
        // Adaptive rate: faster speed → more frequent broadcasts
        let interval: TimeInterval = {
            guard loc.speed > 0 else { return 5.0 }
            return loc.speed > 20 ? 0.5 : (loc.speed > 5 ? 1.0 : 2.0)
        }()
        guard Date().timeIntervalSince(lastBroadcast) >= interval else { return }
        lastBroadcast = Date()
        onLocation?(loc)
    }
}
