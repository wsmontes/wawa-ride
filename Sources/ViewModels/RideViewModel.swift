import Foundation
import SwiftUI
import CoreLocation
import MultipeerConnectivity
import Network
import os.log

/// Central ViewModel orchestrating MultipeerConnectivity, WebRTC, and Location.
@MainActor
@Observable
final class RideViewModel {

    // MARK: - Services

    let multipeer = MultipeerService()
    let blePairing = BLEPairingService()
    let locationService = LocationService()
    private(set) var webRTC: WebRTCService!

    // MARK: - Published state

    var currentRiders: [Rider] = []
    var isPairing = false
    var isRideActive = false
    var localRiderID: String = ""
    var errorMessage: String?

    private let log = Logger(subsystem: "com.wawaride", category: "ViewModel")

    /// Tracks whether we've already initiated a WebRTC connection for a peer.
    private var webrtcInitiatedFor: Set<String> = []
    /// Chunk reassembly buffer: riderID → [chunkIndex: payload]
    private var chunkBuffers: [String: [Int: Data]] = [:]

    // MARK: - Init

    init() {
        localRiderID = loadOrCreateRiderID()
        webRTC = WebRTCService(localRiderID: localRiderID)
        setupSignalingBridge()
    }

    func onAppLaunch() {
        AppLogger.shared.info("App launched — starting BLE + MC")
        locationService.requestPermission()
        forceLocalNetwork()
        multipeer.startPairing()
        blePairing.start()
    }

    /// Workaround: dummy NWBrowser to trigger local network permission on iOS 18
    private func forceLocalNetwork() {
        let browser = NWBrowser(
            for: .bonjour(type: "_wawaride-pair._tcp", domain: nil),
            using: NWParameters()
        )
        browser.stateUpdateHandler = { state in
            if case .ready = state { browser.cancel() }
        }
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { browser.cancel() }
    }

    // MARK: - Bridge Setup

    private func setupSignalingBridge() {
        // MC → WebRTC: signaling data received via Bluetooth
        multipeer.onSignalingData = { [weak self] data, peerID in
            self?.webRTC.onSignalingReceived(data, from: peerID.displayName)
        }

        // WebRTC → BLE: outgoing signaling with chunking
        webRTC.onOutgoingSignaling = { [weak self] data, riderID in
            guard let self else { return }
            DispatchQueue.main.async {
                if data.count <= 500 {
                    // Small — send directly
                    self.blePairing.send(data)
                    AppLogger.shared.info("BLE sent \(data.count)b (single)")
                } else {
                    // Large — split into chunks
                    let chunkSize = 500
                    let total = data.count
                    let chunks = (total + chunkSize - 1) / chunkSize
                    for i in 0..<chunks {
                        let start = i * chunkSize
                        let end = min(start + chunkSize, total)
                        var header = Data([UInt8(chunks), UInt8(i)])
                        header.append(contentsOf: data[start..<end])
                        self.blePairing.send(header)
                    }
                    AppLogger.shared.info("BLE sent \(total)b in \(chunks) chunks")
                }
            }
        }

        // WebRTC DataChannel: remote location updates
        webRTC.onDataReceived = { [weak self] data, riderID in
            guard let self, let update = LocationUpdate.decode(data) else { return }
            DispatchQueue.main.async {
                self.applyLocationUpdate(update)
            }
        }

        // MC peer connected → just acknowledge, WebRTC starts on "Iniciar Passeio"
        multipeer.onPeerConnected = { [weak self] _ in
            // No WebRTC yet — just MC connection is established.
            // WebRTC offers are created in startRide() when user taps "Iniciar Passeio".
        }

        // MC peer disconnected → clean up
        multipeer.onPeerDisconnected = { [weak self] peerID in
            let riderID = peerID.displayName
            self?.webRTC.disconnect(peer: riderID)
            self?.currentRiders.removeAll { $0.id == riderID }
            self?.webrtcInitiatedFor.remove(riderID)
        }

        // BLE connected → ping test first, then WebRTC
        blePairing.onPeerConnected = { [weak self] riderID in
            guard let self, !self.webrtcInitiatedFor.contains(riderID) else { return }
            self.webrtcInitiatedFor.insert(riderID)
            // Send ping to verify BLE data flow
            let ping = "PING:\(self.localRiderID)".data(using: .utf8)!
            self.blePairing.send(ping)
            AppLogger.shared.info("BLE PING sent to \(riderID)")
            // Create WebRTC offer after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AppLogger.shared.info("Creating WebRTC offer for \(riderID)")
                self.webRTC.createOffer(for: riderID)
            }
        }

        // BLE data received — check for PING/PONG, then route to WebRTC or chunk buffer
        blePairing.onDataReceived = { [weak self] data, riderID in
            guard let self else { return }
            let str = String(data: data, encoding: .utf8) ?? ""
            if str.hasPrefix("PING:") {
                AppLogger.shared.info("BLE PING received from \(riderID), sending PONG")
                let pong = "PONG:\(self.localRiderID)".data(using: .utf8)!
                self.blePairing.send(pong)
                return
            }
            if str.hasPrefix("PONG:") {
                AppLogger.shared.info("BLE PONG received from \(riderID) — data flow CONFIRMED ✅")
                return
            }
            // WebRTC signaling — detect chunked vs direct
            if data.count >= 2 && data[0] > 1 {
                // Multi-chunk: byte 0 = total chunks, byte 1 = chunk index
                let totalChunks = Int(data[0])
                let chunkIndex = Int(data[1])
                let payload = Data(data.dropFirst(2))
                self.reassembleChunk(chunk: chunkIndex, total: totalChunks, payload: payload, from: riderID)
            } else {
                // Single message (or PING/PONG handled above)
                self.webRTC.onSignalingReceived(data, from: riderID)
            }
        }
    }

    // MARK: - Pairing

    func startPairing() {
        isPairing = true
        errorMessage = nil
        multipeer.startPairing()
        // Request location permission early so GPS is warm when ride starts
        locationService.requestPermission()
    }

    func stopPairing() {
        isPairing = false
        multipeer.stopPairing()
        webrtcInitiatedFor.removeAll()
    }

    func invitePeer(_ peer: MCPeerID) {
        multipeer.invite(peer: peer)
    }

    // MARK: - Ride

    func startRide() {
        // Warn but allow solo mode
        if multipeer.connectedPeers.isEmpty {
            log.warning("Starting ride with no MC peers — solo mode")
        }

        // Try to start GPS regardless of permission state
        locationService.startUpdating()

        // Add local rider if we have GPS, otherwise map shows waiting state
        if let loc = locationService.currentLocation {
            currentRiders = [Rider(
                id: localRiderID, displayName: "Voce",
                coordinate: loc.coordinate,
                heading: loc.course >= 0 ? loc.course : nil,
                speed: loc.speed >= 0 ? loc.speed : nil,
                lastUpdate: Date(), isConnected: true
            )]
        }

        // Transition to map
        isRideActive = true
        errorMessage = nil

        // Create WebRTC offers for any connected peers
        for peer in multipeer.connectedPeers {
            let riderID = peer.displayName
            guard !webrtcInitiatedFor.contains(riderID) else { continue }
            webrtcInitiatedFor.insert(riderID)
            webRTC.createOffer(for: riderID)
        }

        // Stream GPS → map + WebRTC
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await location in self.locationService.locationUpdates {
                if let idx = self.currentRiders.firstIndex(where: { $0.id == self.localRiderID }) {
                    self.currentRiders[idx].coordinate = location.coordinate
                    self.currentRiders[idx].heading = location.course >= 0 ? location.course : nil
                    self.currentRiders[idx].speed = location.speed >= 0 ? location.speed : nil
                    self.currentRiders[idx].lastUpdate = location.timestamp
                } else {
                    self.currentRiders.append(Rider(
                        id: self.localRiderID, displayName: "Voce",
                        coordinate: location.coordinate,
                        heading: location.course >= 0 ? location.course : nil,
                        speed: location.speed >= 0 ? location.speed : nil,
                        lastUpdate: location.timestamp, isConnected: true
                    ))
                }
                let update = LocationUpdate(riderID: self.localRiderID, location: location)
                if let encoded = update.encode() {
                    self.webRTC.broadcast(encoded)
                }
            }
        }

        log.info("Ride started — MC: \(self.multipeer.connectedPeers.count) peers, GPS: \(self.locationService.isUpdating)")
    }

    func stopRide() {
        isRideActive = false
        locationService.stopUpdating()
        currentRiders.removeAll()
        for riderID in webrtcInitiatedFor {
            webRTC.disconnect(peer: riderID)
        }
        webrtcInitiatedFor.removeAll()
    }

    // MARK: - Helpers

    private func applyLocationUpdate(_ update: LocationUpdate) {
        if let index = currentRiders.firstIndex(where: { $0.id == update.riderID }) {
            currentRiders[index].coordinate = update.coordinate
            currentRiders[index].heading = update.heading
            currentRiders[index].speed = update.speed
            currentRiders[index].lastUpdate = Date(timeIntervalSince1970: update.timestamp)
        } else {
            currentRiders.append(Rider(
                id: update.riderID,
                displayName: update.riderID,
                coordinate: update.coordinate,
                heading: update.heading,
                speed: update.speed,
                lastUpdate: Date(timeIntervalSince1970: update.timestamp),
                isConnected: true
            ))
        }
    }

    private func reassembleChunk(chunk: Int, total: Int, payload: Data, from riderID: String) {
        if chunkBuffers[riderID] == nil { chunkBuffers[riderID] = [:] }
        chunkBuffers[riderID]?[chunk] = payload
        if chunkBuffers[riderID]?.count == total {
            // All chunks received — reassemble
            var full = Data()
            for i in 0..<total {
                if let c = chunkBuffers[riderID]?[i] { full.append(c) }
            }
            chunkBuffers.removeValue(forKey: riderID)
            webRTC.onSignalingReceived(full, from: riderID)
        }
    }

    private func loadOrCreateRiderID() -> String {
        let key = "wawa_local_rider_id"
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }
        let newID = "rider-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}
