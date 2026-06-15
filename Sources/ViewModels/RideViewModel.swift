import Foundation
import SwiftUI
import CoreLocation
import MultipeerConnectivity
import os.log

/// Central ViewModel orchestrating MultipeerConnectivity, WebRTC, and Location.
@MainActor
@Observable
final class RideViewModel {

    // MARK: - Services

    let multipeer = MultipeerService()
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

    // MARK: - Init

    init() {
        localRiderID = loadOrCreateRiderID()
        webRTC = WebRTCService(localRiderID: localRiderID)
        setupSignalingBridge()
        // Request GPS permission immediately on first launch
        locationService.requestPermission()
    }

    // MARK: - Bridge Setup

    private func setupSignalingBridge() {
        // MC → WebRTC: signaling data received via Bluetooth
        multipeer.onSignalingData = { [weak self] data, peerID in
            self?.webRTC.onSignalingReceived(data, from: peerID.displayName)
        }

        // WebRTC → MC: outgoing signaling (dispatched to main for thread safety)
        webRTC.onOutgoingSignaling = { [weak self] data, riderID in
            guard let self else { return }
            DispatchQueue.main.async {
                if let peer = self.multipeer.connectedPeers.first(where: { $0.displayName == riderID }) {
                    self.multipeer.sendSignaling(data, to: peer)
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
