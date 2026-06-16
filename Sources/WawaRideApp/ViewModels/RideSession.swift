import Foundation
import CoreLocation
// Self-module imports commented for flat-target compilation:
// import BitFoundation, WawaMesh, WawaMap, WawaNavigation, WawaPersistence
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
    @Published var groupID: String = ""
    private var staleTimer: Timer?
    private var currentRide: Ride?
    private var peerVisibility: [String: Visibility] = [:]  // peerID → visibility

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
            Task { @MainActor in self?.applyLocation(payload, from: peerName, isMember: true) }
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
        groupID = UUID().uuidString  // unique group per ride
        mesh.start()
        broadcastAnnounce()
    }

    func startAsFollower() {
        isLeader = false
        phase = .pairing
        mesh.start()
    }

    func joinWithPIN(_ pin: String) {
        let payload = "JOIN:\(pin)".data(using: .utf8)!
        mesh.send(BitchatPacket(type: 0x05, senderID: mesh.ble.localPeerID, payload: payload))
    }

    func confirmPairing() { startRide() }

    /// Broadcast announce with groupID and visibility (every ~30s during ride).
    private func broadcastAnnounce() {
        let announce = AnnouncePayload(nickname: "Rider", groupID: groupID, visibility: .public)
        guard let data = try? JSONEncoder().encode(announce) else { return }
        mesh.send(BitchatPacket(type: MessageType.announce.rawValue, senderID: mesh.ble.localPeerID, payload: data))
    }

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
        mesh.send(BitchatPacket(type: 0x02, senderID: mesh.ble.localPeerID, payload: compact.encode()))
        // Update CRDT doc
        let id = mesh.ble.localPeerID.hex
        syncDoc.updateRider(id: id, lat: payload.lat, lon: payload.lon,
                           heading: payload.heading, speed: payload.speed)
    }

    // MARK: - Receiving

    private func handleMeshPacket(_ packet: BitchatPacket) {
        let peerID = packet.senderID.hex

        switch packet.type {
        case MessageType.announce.rawValue:
            // Track peer's group and visibility
            guard let announce = try? JSONDecoder().decode(AnnouncePayload.self, from: packet.payload) else { return }
            peerVisibility[peerID] = announce.visibility
            // If hidden and not our group, ignore completely
            if announce.visibility == .hidden && announce.groupID != groupID { return }
            // If groupOnly and not our group, ignore
            if announce.visibility == .groupOnly && announce.groupID != groupID { return }

        case 0x02:  // locationUpdate
            // Visibility filter: check last known visibility for this peer
            let vis = peerVisibility[peerID] ?? .public
            if vis == .hidden { return }

            let isMember = peerVisibility[peerID] != nil  // has announced = we know their group
                && (peerVisibility[peerID] == .public || groupID.isEmpty)  // simplified for MVP

            // Decode compact binary (12 bytes) or JSON fallback
            if let loc = CompactLocation.decode(packet.payload) {
                let payload = LocationPayload(lat: loc.latitude, lon: loc.longitude,
                                              heading: loc.headingDegrees, speed: loc.speedMps,
                                              accuracy: 10, timestamp: Date().timeIntervalSince1970)
                applyLocation(payload, from: peerID, isMember: true)
            } else if let p = try? JSONDecoder().decode(LocationPayload.self, from: packet.payload) {
                applyLocation(p, from: peerID, isMember: true)
            }
        case 0x03:  // routeShare
            if let coords = try? JSONDecoder().decode([[Double]].self, from: packet.payload) {
                routeCoords = coords.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
                groupNav.setSharedRoute(routeCoords)
            }
        default: break
        }
    }

    private func applyLocation(_ p: LocationPayload, from id: String, isMember: Bool = true) {
        let coord = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        if let idx = riders.firstIndex(where: { $0.id == id }) {
            riders[idx].coordinate = coord
            riders[idx].heading = p.heading
            riders[idx].speed = p.speed
            riders[idx].lastSeen = Date()
        } else {
            riders.append(RiderAnnotation(id: id, displayName: "Rider \(id.prefix(4))",
                                          coordinate: coord, heading: p.heading, speed: p.speed,
                                          isMember: isMember))
        }
        if isMember { groupNav.appendLeaderPosition(coord) }
    }

    private func handleSync(_ data: Data, from peer: String) {
        // TODO: per-peer SyncState management
        // For now, just log receipt
    }

    private func purgeStaleRiders() {
        riders.removeAll { Date().timeIntervalSince($0.lastSeen) > MeshConstants.riderRemoveTimeout }
    }
}
