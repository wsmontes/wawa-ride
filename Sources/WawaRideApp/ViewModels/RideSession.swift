import Foundation
import CoreLocation
import WawaMesh
import WawaMap
import WawaNavigation

@MainActor
final class RideSession: ObservableObject {
    let mesh = TransportCoordinator()
    let tileManager: OfflineTileManager
    let routeService: RouteService
    let mapMatching: MapMatchingService
    let groupNav: GroupNavigationCoordinator
    let locationTracker: SmartLocationTracker

    @Published var riders: [RiderAnnotation] = []
    @Published var routeCoords: [CLLocationCoordinate2D] = []
    @Published var phase: Phase = .idle
    @Published var pairingPIN: String = ""
    private var staleTimer: Timer?

    enum Phase { case idle, pairing, riding, navigating }

    init() {
        let valhallaBase = URL(string: "http://localhost:8002")!
        tileManager = OfflineTileManager(styleURL: URL(string: "https://demotiles.maplibre.org/style.json")!)
        routeService = RouteService(baseURL: valhallaBase, profile: "motorcycle")
        mapMatching = MapMatchingService(baseURL: valhallaBase)
        groupNav = GroupNavigationCoordinator(mapMatching: mapMatching)
        locationTracker = SmartLocationTracker()

        mesh.onPacketReceived = { [weak self] packet in
            Task { @MainActor in self?.handlePacket(packet) }
        }
    }

    func startPairing() {
        phase = .pairing
        pairingPIN = String(format: "%04d", Int.random(in: 0...9999))
        mesh.start()
    }

    func joinWithPIN(_ pin: String) {
        // In MVP, PIN matching is validated by including the PIN in the announce payload.
        // Peers with same PIN are accepted into the group.
        let payload = "JOIN:\(pin)".data(using: .utf8)!
        let packet = MeshPacket(type: .groupControl, senderID: mesh.ble.localPeerID, payload: payload)
        mesh.send(packet)
    }

    func confirmPairing() {
        startRide()
    }

    func startRide() {
        phase = .riding
        mesh.start()
        locationTracker.start { [weak self] location in
            self?.broadcastLocation(location)
        }
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.purgeStaleRiders() }
        }
    }

    func stopRide() {
        phase = .idle
        mesh.stop()
        locationTracker.stop()
        staleTimer?.invalidate()
        staleTimer = nil
        riders.removeAll()
        routeCoords.removeAll()
    }

    private func purgeStaleRiders() {
        riders.removeAll { Date().timeIntervalSince($0.lastSeen) > MeshConfig.riderRemoveTimeout }
    }

    private func broadcastLocation(_ location: CLLocation) {
        let payload = LocationPayload(
            lat: location.coordinate.latitude, lon: location.coordinate.longitude,
            heading: location.course >= 0 ? location.course : nil,
            speed: location.speed >= 0 ? location.speed : nil,
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp.timeIntervalSince1970
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let packet = MeshPacket(type: .locationUpdate, senderID: mesh.ble.localPeerID, payload: data)
        mesh.send(packet)
    }

    private func handlePacket(_ packet: MeshPacket) {
        switch packet.type {
        case .locationUpdate:
            guard let p = try? JSONDecoder().decode(LocationPayload.self, from: packet.payload) else { return }
            let id = packet.senderID.hex
            let coord = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
            if let idx = riders.firstIndex(where: { $0.id == id }) {
                riders[idx].coordinate = coord
                riders[idx].heading = p.heading
                riders[idx].speed = p.speed
                riders[idx].lastSeen = Date()
            } else {
                riders.append(RiderAnnotation(id: id, displayName: "Rider \(id.prefix(4))", coordinate: coord,
                                              heading: p.heading, speed: p.speed, lastSeen: Date()))
            }
            groupNav.appendLeaderPosition(coord)
        case .routeShare:
            if let coords = try? JSONDecoder().decode([[Double]].self, from: packet.payload) {
                let route = coords.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
                routeCoords = route
                groupNav.setSharedRoute(route)
            }
        default: break
        }
    }
}
