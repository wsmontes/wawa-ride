import Foundation
import SwiftUI
import CoreLocation
import MultipeerConnectivity
import os.log

/// Central ViewModel that orchestrates MultipeerConnectivity, WebRTC, and Location services.
@MainActor
@Observable
final class RideViewModel {

    // MARK: - Services (multiPeer is non-private for PairingView access)

    let multipeer = MultipeerService()
    private let locationService = LocationService()
    private var webRTC: WebRTCService!

    // MARK: - State

    var currentRiders: [Rider] = []
    var isPairing = false
    var isRideActive = false
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var localRiderID: String = ""

    private let log = Logger(subsystem: "com.wawaride", category: "ViewModel")

    // MARK: - Init

    init() {
        localRiderID = loadOrCreateRiderID()
        webRTC = WebRTCService(localRiderID: localRiderID)
    }

    // MARK: - Pairing

    func startPairing() {
        isPairing = true
        multipeer.startPairing()
        multipeer.startBrowsing()

        // When signaling data arrives via MC, forward to WebRTC
        multipeer.onSignalingData = { [weak self] data, peerID in
            guard let self else { return }
            let riderID = peerID.displayName
            self.webRTC.onSignalingReceived(data, from: riderID)
        }
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
        isRideActive = true
        locationService.requestPermission()
        locationService.startUpdating()

        // Wire WebRTC → MC signaling
        webRTC.onOutgoingSignaling = { [weak self] data, riderID in
            guard let self else { return }
            // Find the MCPeerID matching this riderID and send
            if let peer = self.multipeer.connectedPeers.first(where: { $0.displayName == riderID }) {
                self.multipeer.sendSignaling(data, to: peer)
            }
        }

        // Wire WebRTC data received
        webRTC.onDataReceived = { [weak self] data, riderID in
            guard let self, let update = LocationUpdate.decode(data) else { return }
            self.applyLocationUpdate(update)
        }

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
    }

    func stopRide() {
        isRideActive = false
        locationService.stopUpdating()
        currentRiders.removeAll()
    }

    // MARK: - WebRTC peer management

    func connectToRider(_ riderID: String) {
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
