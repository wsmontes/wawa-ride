import SwiftUI
import CoreLocation

@main
struct WawaRideApp: App {
    @StateObject private var app = WawaAppState()

    var body: some Scene {
        WindowGroup {
            RideMainView()
                .environmentObject(app)
        }
    }
}

/// Global app state — holds mesh, gps, and rider list.
@MainActor
final class WawaAppState: ObservableObject {
    let mesh = MeshService()
    let locationTracker = LocationTracker()
    @Published var riders: [RiderAnnotation] = []
    @Published var routeCoords: [CLLocationCoordinate2D] = []

    /// My own PeerID as rider ID
    var myId: String { mesh.localPeerIDHex }

    init() {
        // When we receive a message via BLE mesh, extract location
        mesh.onMessageReceived = { [weak self] peerId, text in
            guard let self else { return }
            // Parse: "LOC:lat,lon,heading,speed"
            if text.hasPrefix("LOC:"), let loc = self.parseLocation(text) {
                self.upsertRider(id: peerId, coord: loc.coord, heading: loc.heading, speed: loc.speed)
            }
        }

        // Broadcast my location every 2 seconds
        locationTracker.onLocation = { [weak self] location in
            guard let self, self.mesh.isRunning else { return }
            let msg = String(format: "LOC:%.6f,%.6f,%.1f,%.1f",
                             location.coordinate.latitude,
                             location.coordinate.longitude,
                             location.course >= 0 ? location.course : 0,
                             location.speed >= 0 ? location.speed : 0)
            self.mesh.broadcastTest(msg)
            // Update my own position
            self.upsertRider(id: self.myId, coord: location.coordinate,
                             heading: location.course >= 0 ? location.course : nil,
                             speed: location.speed >= 0 ? location.speed : nil)
        }
    }

    func start() {
        mesh.start()
        locationTracker.start()
    }

    func stop() {
        mesh.stop()
        locationTracker.stop()
    }

    private func upsertRider(id: String, coord: CLLocationCoordinate2D, heading: Double?, speed: Double?) {
        if let idx = riders.firstIndex(where: { $0.id == id }) {
            riders[idx].coordinate = coord
            riders[idx].heading = heading
            riders[idx].speed = speed
            riders[idx].lastSeen = Date()
        } else {
            let isMe = id == myId
            riders.append(RiderAnnotation(
                id: id,
                displayName: isMe ? "You" : String(id.prefix(6)),
                coordinate: coord,
                heading: heading,
                speed: speed,
                isLeader: isMe,
                isMember: true
            ))
        }
    }

    private func parseLocation(_ text: String) -> (coord: CLLocationCoordinate2D, heading: Double?, speed: Double?)? {
        let parts = text.dropFirst(4).split(separator: ",")
        guard parts.count >= 2,
              let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        let hdg = parts.count > 2 ? Double(parts[2]) : nil
        let spd = parts.count > 3 ? Double(parts[3]) : nil
        return (CLLocationCoordinate2D(latitude: lat, longitude: lon), hdg, spd)
    }
}

/// Minimal GPS tracker — fires location updates at ~1 Hz.
final class LocationTracker: NSObject, ObservableObject, @unchecked Sendable {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.requestAlwaysAuthorization()
    }

    func start() { manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }
}

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.onLocation?(loc) }
    }
}
