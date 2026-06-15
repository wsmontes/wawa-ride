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
    private let locationService = LocationService()
    private var webRTC: WebRTCService!

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
    }

    // MARK: - Bridge Setup

    private func setupSignalingBridge() {
        // MC → WebRTC: signaling data received via Bluetooth
        multipeer.onSignalingData = { [weak self] data, peerID in
            self?.webRTC.onSignalingReceived(data, from: peerID.displayName)
        }

        // WebRTC → MC: outgoing signaling (SDP/ICE)
        webRTC.onOutgoingSignaling = { [weak self] data, riderID in
            guard let self else { return }
            if let peer = self.multipeer.connectedPeers.first(where: { $0.displayName == riderID }) {
                self.multipeer.sendSignaling(data, to: peer)
            }
        }

        // WebRTC DataChannel: remote location updates
        webRTC.onDataReceived = { [weak self] data, riderID in
            guard let self, let update = LocationUpdate.decode(data) else { return }
            self.applyLocationUpdate(update)
        }

        // MC peer connected → wait briefly then init WebRTC if no incoming offer
        multipeer.onPeerConnected = { [weak self] peerID in
            guard let self else { return }
            let riderID = peerID.displayName
            guard !self.webrtcInitiatedFor.contains(riderID) else { return }
            self.webrtcInitiatedFor.insert(riderID)

            // Polite delay: give the other side time to send an offer first.
            // The peer with the lexicographically greater name waits longer.
            let isPolite = self.localRiderID > riderID
            let delay: UInt64 = isPolite ? 1_500_000_000 : 500_000_000

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                // Only create offer if peer is still connected and hasn't already
                // sent us an offer (which would have created a connection already)
                self.webRTC.createOffer(for: riderID)
            }
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
        guard !multipeer.connectedPeers.isEmpty else {
            errorMessage = "Nenhum motociclista pareado."
            return
        }

        isRideActive = true
        errorMessage = nil
        locationService.requestPermission()
        locationService.startUpdating()

        // Stream local location → WebRTC broadcast
        Task { [weak self] in
            guard let self else { return }
            for await location in self.locationService.locationUpdates {
                let update = LocationUpdate(riderID: self.localRiderID, location: location)
                if let encoded = update.encode() {
                    self.webRTC.broadcast(encoded)
                }
            }
        }

        log.info("Ride started with \(self.multipeer.connectedPeers.count) peers")
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
