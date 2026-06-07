import Foundation
import CoreLocation

// MARK: - Hazard Service

/// Manages hazard alerts: mark, confirm, clear, and automatic expiry.

@MainActor
final class HazardService: ObservableObject {
    static let shared = HazardService()

    @Published var activeAlerts: [HazardAlert] = []

    private var expiryTimer: Timer?

    private init() {
        startExpiryTimer()
    }

    // MARK: - Mark Hazard

    func markHazard(type: HazardType, at coordinate: CLLocationCoordinate2D) {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""

        let alert = HazardAlert(
            type: type,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            reportedBy: myName,
            reportedById: myId
        )

        activeAlerts.append(alert)
        sendHazardToMesh(alert)

        // TTS confirmation
        VoiceAssistant.shared.speak(.hazardMarked(type: type))
    }

    // MARK: - Confirm / Clear

    func confirmAlert(_ alertId: String) {
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""

        guard let index = activeAlerts.firstIndex(where: { $0.id == alertId }) else { return }
        if !activeAlerts[index].confirmedBy.contains(myName) {
            activeAlerts[index].confirmedBy.append(myName)
        }

        sendHazardActionToMesh(alertId: alertId, action: .confirm, riderName: myName, riderId: myId)
    }

    func clearAlert(_ alertId: String) {
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""

        guard let index = activeAlerts.firstIndex(where: { $0.id == alertId }) else { return }
        if !activeAlerts[index].clearedBy.contains(myName) {
            activeAlerts[index].clearedBy.append(myName)
        }

        sendHazardActionToMesh(alertId: alertId, action: .clear, riderName: myName, riderId: myId)
    }

    // MARK: - Incoming from Mesh

    func handleIncomingAlert(_ alert: HazardAlert) {
        // Dedup
        guard !activeAlerts.contains(where: { $0.id == alert.id }) else { return }
        activeAlerts.append(alert)

        // TTS for nearby hazards
        if let myLocation = LocationService.shared.currentLocation {
            let distance = myLocation.coordinate.distance(from: alert.coordinate)
            if distance < 500 {
                VoiceAssistant.shared.speak(.hazardNearby(type: alert.type, distance: Int(distance)))
            }
        }
    }

    func handleConfirmAction(alertId: String, riderName: String) {
        guard let index = activeAlerts.firstIndex(where: { $0.id == alertId }) else { return }
        if !activeAlerts[index].confirmedBy.contains(riderName) {
            activeAlerts[index].confirmedBy.append(riderName)
        }
    }

    func handleClearAction(alertId: String, riderName: String) {
        guard let index = activeAlerts.firstIndex(where: { $0.id == alertId }) else { return }
        if !activeAlerts[index].clearedBy.contains(riderName) {
            activeAlerts[index].clearedBy.append(riderName)
        }
    }

    // MARK: - Expiry

    private func startExpiryTimer() {
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupExpired()
            }
        }
    }

    private func cleanupExpired() {
        activeAlerts.removeAll { $0.isExpired }
    }

    // MARK: - Send via Mesh

    private func sendHazardToMesh(_ alert: HazardAlert) {
        let payload = HazardAlertPayload(alert: alert)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let meshPayload = MeshPayload(
            type: .hazardAlert,
            senderId: alert.reportedById,
            senderName: alert.reportedBy,
            rideId: AppState.shared.currentRideId ?? "",
            ttl: 10,
            priority: .critical,
            payload: data
        )

        TransportManager.shared.send(meshPayload)
    }

    private func sendHazardActionToMesh(alertId: String, action: HazardActionType, riderName: String, riderId: String) {
        let actionPayload = HazardActionPayload(
            alertId: alertId,
            riderName: riderName,
            riderId: riderId
        )
        guard let data = try? JSONEncoder().encode(actionPayload) else { return }

        let type: MeshPayloadType = action == .confirm ? .hazardConfirm : .hazardClear

        let meshPayload = MeshPayload(
            type: type,
            senderId: riderId,
            senderName: riderName,
            rideId: AppState.shared.currentRideId ?? "",
            ttl: 8,
            priority: .high,
            payload: data
        )

        TransportManager.shared.send(meshPayload)
    }
}

enum HazardActionType {
    case confirm
    case clear
}
