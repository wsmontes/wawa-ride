import Foundation
import CoreLocation
import Combine

/// Manages ride lifecycle: idle → proposed → active → completed.
/// Owns the MeshService, GPS tracker, and rider list.
@MainActor
final class RideState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case creating          // user is filling in ride details
        case proposed(String)  // PIN displayed, waiting for riders (associated: groupID)
        case active            // ride started, GPS + map active
        case completed         // ride ended
    }

    @Published var phase: Phase = .idle
    @Published var rideName: String = "Sunday Ride"
    @Published var pin: String = ""
    @Published var groupID: String = ""
    @Published var connectedPeerCount: Int = 0
    @Published var riders: [RiderAnnotation] = []
    @Published var routeCoords: [CLLocationCoordinate2D] = []

    let mesh = MeshService()
    private let locationTracker = LocationTracker()
    private var announceTimer: Timer?
    private var staleTimer: Timer?

    var myId: String { mesh.localPeerIDHex }

    init() {
        mesh.onMessageReceived = { [weak self] peerId, text in
            Task { @MainActor in self?.handleMessage(peerId: peerId, text: text) }
        }
    }

    // MARK: - Actions

    func createRide() {
        pin = String(format: "%04d", Int.random(in: 0...9999))
        groupID = UUID().uuidString
        phase = .proposed(groupID)
        mesh.start()
        startAnnouncing()
    }

    func cancelRide() {
        phase = .idle
        mesh.stop()
        announceTimer?.invalidate()
        pin = ""
        groupID = ""
    }

    func startRide() {
        phase = .active
        locationTracker.onLocation = { [weak self] loc in
            Task { @MainActor in self?.broadcastLocation(loc) }
        }
        locationTracker.start()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.purgeStaleRiders() }
        }
    }

    func stopRide() {
        phase = .idle
        mesh.stop()
        locationTracker.stop()
        announceTimer?.invalidate()
        staleTimer?.invalidate()
        riders.removeAll()
        connectedPeerCount = 0
    }

    // MARK: - Internal

    private func startAnnouncing() {
        let announce = AnnouncePayload(nickname: "Rider", groupID: groupID, visibility: .groupOnly)
        guard let data = try? JSONEncoder().encode(announce) else { return }
        announceTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.mesh.sendPacket(type: MessageType.announce.rawValue, payload: data)
        }
    }

    private func broadcastLocation(_ loc: CLLocation) {
        let msg = String(format: "LOC:%.6f,%.6f,%.1f,%.1f",
                         loc.coordinate.latitude, loc.coordinate.longitude,
                         loc.course >= 0 ? loc.course : 0,
                         loc.speed >= 0 ? loc.speed : 0)
        mesh.broadcastTest(msg)
        upsertRider(id: myId, coord: loc.coordinate,
                    heading: loc.course >= 0 ? loc.course : nil,
                    speed: loc.speed >= 0 ? loc.speed : nil)
    }

    private func handleMessage(peerId: String, text: String) {
        if text.hasPrefix("LOC:"), let loc = parseLocation(text) {
            upsertRider(id: peerId, coord: loc.coord, heading: loc.heading, speed: loc.speed)
        }
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
                id: id, displayName: isMe ? "You" : String(id.prefix(6)),
                coordinate: coord, heading: heading, speed: speed,
                isLeader: isMe, isMember: true
            ))
        }
        connectedPeerCount = riders.count
    }

    private func parseLocation(_ text: String) -> (coord: CLLocationCoordinate2D, heading: Double?, speed: Double?)? {
        let parts = text.dropFirst(4).split(separator: ",")
        guard parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        let hdg = parts.count > 2 ? Double(parts[2]) : nil
        let spd = parts.count > 3 ? Double(parts[3]) : nil
        return (CLLocationCoordinate2D(latitude: lat, longitude: lon), hdg, spd)
    }

    private func purgeStaleRiders() {
        riders.removeAll { Date().timeIntervalSince($0.lastSeen) > 120 }
    }
}
