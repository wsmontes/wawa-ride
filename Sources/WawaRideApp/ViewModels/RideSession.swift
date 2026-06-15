import Foundation
import CoreLocation
import WawaMesh
import WawaMap
import WawaNavigation
import WawaPersistence
import Automerge

@MainActor
final class RideSession: ObservableObject {
    let mesh = TransportCoordinator()
    let tileManager = OfflineTileManager()
    let routeService: RouteService
    let mapMatching: MapMatchingService
    let groupNav: GroupNavigationCoordinator
    let locationTracker = SmartLocationTracker()
    let db: AppDatabase
    let syncDoc: RideSyncDocument

    @Published var riders: [RiderAnnotation] = []
    @Published var routeCoords: [CLLocationCoordinate2D] = []
    @Published var phase: Phase = .idle
    @Published var pairingPIN: String = ""
    @Published var isLeader = false
    private var staleTimer: Timer?
    private var currentRide: Ride?

    enum Phase { case idle, pairing, riding, navigating }

    init() {
        let valhallaBase = URL(string: "http://localhost:8002")!
        routeService = RouteService(baseURL: valhallaBase, profile: "motorcycle")
        mapMatching = MapMatchingService(baseURL: valhallaBase)
        groupNav = GroupNavigationCoordinator(mapMatching: mapMatching)
        db = try! AppDatabase()
        syncDoc = RideSyncDocument(actorId: mesh.ble.localPeerID)

        // BLE mesh packets (location via binary protocol)
        mesh.onPacketReceived = { [weak self] packet in
            Task { @MainActor in self?.handleMeshPacket(packet) }
        }
        // MultipeerKit location (Codable, fast foreground path)
        mesh.onLocationReceived = { [weak self] payload, peerName in
            Task { @MainActor in self?.applyLocation(payload, from: peerName) }
        }
        // Automerge sync messages
        mesh.onSyncMessage = { [weak self] data, peer in
            Task { @MainActor in self?.handleSync(data, from: peer) }
        }
    }

    // MARK: - Pairing (simplified: leader creates, follower joins)

    func startAsLeader() {
        isLeader = true
        phase = .pairing
        pairingPIN = String(format: "%04d", Int.random(in: 0...9999))
        mesh.start()
    }

    func startAsFollower() {
        isLeader = false
        phase = .pairing
        mesh.start()
    }

    func joinWithPIN(_ pin: String) {
        let payload = "JOIN:\(pin)".data(using: .utf8)!
        mesh.send(MeshPacket(type: .groupControl, senderID: mesh.ble.localPeerID, payload: payload))
    }

    func confirmPairing() { startRide() }

    // MARK: - Ride Lifecycle

    func startRide() {
        phase = .riding
        currentRide = try? db.startRide(isLeader: true)
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
        if var ride = currentRide { try? db.endRide(&ride) }
        currentRide = nil
        mesh.stop()
        locationTracker.stop()
        staleTimer?.invalidate()
        staleTimer = nil
        riders.removeAll()
        routeCoords.removeAll()
    }

    // MARK: - Broadcasting

    private func broadcastLocation(_ location: CLLocation) {
        let payload = LocationPayload(
            lat: location.coordinate.latitude, lon: location.coordinate.longitude,
            heading: location.course >= 0 ? location.course : nil,
            speed: location.speed >= 0 ? location.speed : nil,
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp.timeIntervalSince1970
        )
        // Fast path: MultipeerKit (Codable, foreground)
        mesh.broadcastLocation(payload)
        // Resilient path: BLE mesh (compact binary 12 bytes, background, multi-hop)
        let compact = CompactLocation(latitude: payload.lat, longitude: payload.lon,
                                      heading: payload.heading, speed: payload.speed)
        mesh.send(MeshPacket(type: .locationUpdate, senderID: mesh.ble.localPeerID, payload: compact.encode()))
        // Update CRDT doc
        let id = mesh.ble.localPeerID.hex
        syncDoc.updateRider(id: id, lat: payload.lat, lon: payload.lon,
                           heading: payload.heading, speed: payload.speed)
    }

    // MARK: - Receiving

    private func handleMeshPacket(_ packet: MeshPacket) {
        switch packet.type {
        case .locationUpdate:
            // Try compact binary first (12 bytes), fall back to JSON
            if let loc = CompactLocation.decode(packet.payload) {
                let payload = LocationPayload(lat: loc.latitude, lon: loc.longitude,
                                              heading: loc.headingDegrees, speed: loc.speedMps,
                                              accuracy: 10, timestamp: Date().timeIntervalSince1970)
                applyLocation(payload, from: packet.senderID.hex)
            } else if let p = try? JSONDecoder().decode(LocationPayload.self, from: packet.payload) {
                applyLocation(p, from: packet.senderID.hex)
            }
        case .routeShare:
            if let coords = try? JSONDecoder().decode([[Double]].self, from: packet.payload) {
                routeCoords = coords.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
                groupNav.setSharedRoute(routeCoords)
            }
        default: break
        }
    }

    private func applyLocation(_ p: LocationPayload, from id: String) {
        let coord = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        if let idx = riders.firstIndex(where: { $0.id == id }) {
            riders[idx].coordinate = coord
            riders[idx].heading = p.heading
            riders[idx].speed = p.speed
            riders[idx].lastSeen = Date()
        } else {
            riders.append(RiderAnnotation(id: id, displayName: "Rider \(id.prefix(4))",
                                          coordinate: coord, heading: p.heading, speed: p.speed))
        }
        groupNav.appendLeaderPosition(coord)
    }

    private func handleSync(_ data: Data, from peer: String) {
        // TODO: per-peer SyncState management
        // For now, just log receipt
    }

    private func purgeStaleRiders() {
        riders.removeAll { Date().timeIntervalSince($0.lastSeen) > MeshConfig.riderRemoveTimeout }
    }
}
