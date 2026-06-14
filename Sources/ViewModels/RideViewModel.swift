import Foundation
import SwiftUI
import CoreLocation
import MultipeerConnectivity
import os.log

/// Central ViewModel that orchestrates MultipeerConnectivity, WebRTC, and Location services.
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

        // WebRTC → MC: outgoing signaling (SDP/ICE) needs to go to peer
        webRTC.onOutgoingSignaling = { [weak self] data, riderID in
            guard let self else { return }
            if let peer = self.multipeer.connectedPeers.first(where: { $0.displayName == riderID }) {
                self.multipeer.sendSignaling(data, to: peer)
            } else {
                self.log.warning("No MC peer found for riderID: \(riderID)")
            }
        }

        // WebRTC DataChannel: remote location updates received
        webRTC.onDataReceived = { [weak self] data, riderID in
            guard let self, let update = LocationUpdate.decode(data) else { return }
            self.applyLocationUpdate(update)
        }

        // MC peer connected → create WebRTC offer
        multipeer.onPeerConnected = { [weak self] peerID in
            self?.webRTC.createOffer(for: peerID.displayName)
        }

        // MC peer disconnected → clean up WebRTC
        multipeer.onPeerDisconnected = { [weak self] peerID in
            self?.webRTC.disconnect(peer: peerID.displayName)
            self?.currentRiders.removeAll { $0.id == peerID.displayName }
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
    }

    func invitePeer(_ peer: MCPeerID) {
        multipeer.invite(peer: peer)
    }

    // MARK: - Ride

    func startRide() {
        guard !multipeer.connectedPeers.isEmpty else {
            errorMessage = "Nenhum motociclista pareado. Faça o pareamento primeiro."
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

        // Disconnect all WebRTC peers but keep MC connections
        for rider in currentRiders {
            webRTC.disconnect(peer: rider.id)
        }
    }

    // MARK: - WebRTC peer management

    func connectToRider(_ riderID: String) {
        webRTC.createOffer(for: riderID)
    }

    /// Retry a failed WebRTC connection.
    func retryConnection(to riderID: String) {
        webRTC.disconnect(peer: riderID)
        webRTC.createOffer(for: riderID)
    }

    // MARK: - Helpers

    private func applyLocationUpdate(_ update: LocationUpdate) {
        if let index = currentRiders.firstIndex(where: { $0.id == update.riderID }) {
            currentRiders[index].coordinate = update.coordinate
            currentRiders[index].heading = update.heading
            currentRiders[index].speed = update.speed
            currentRiders[index].lastUpdate = Date(timeIntervalSince1970: update.timestamp)
        } else {
            let rider = Rider(
                id: update.riderID,
                displayName: update.riderID,
                coordinate: update.coordinate,
                heading: update.heading,
                speed: update.speed,
                lastUpdate: Date(timeIntervalSince1970: update.timestamp),
                isConnected: true
            )
            currentRiders.append(rider)
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
