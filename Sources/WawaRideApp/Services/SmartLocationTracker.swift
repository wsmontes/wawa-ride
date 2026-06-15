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
/// ⚠️ IMPORTANT: This tracker keeps GPS active continuously during a ride.
/// This is intentional — unlike OwnTracks (which waits for significant changes),
/// riders need real-time position sharing at 0.5-2 Hz.
/// The blue status bar ("Wawa Ride is using your location") is expected and desired:
/// it reminds riders the app is active, which is important because BLE mesh
/// requires at least one peer in foreground to work (iOS BLE background limitation).
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
/// - For longer tours (8h+): consider dropping to significantLocationChange mode
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
