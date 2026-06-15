import SwiftUI
import MultipeerConnectivity
import CoreLocation

struct DebugOverlay: View {
    let multipeer: MultipeerService
    let webRTC: WebRTCService
    let location: LocationService
    let localRiderID: String

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle bar
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    Circle()
                        .fill(statusDot)
                        .frame(width: 8, height: 8)
                    Text("DEBUG")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    mcSection
                    Divider()
                    webrtcSection
                    Divider()
                    locationSection
                    Divider()
                    turnSection
                }
                .font(.system(size: 10, design: .monospaced))
                .padding(8)
                .background(.ultraThinMaterial.opacity(0.95))
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
        .cornerRadius(10)
    }

    // MARK: - Sections

    private var mcSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("📡 MULTIPEER").fontWeight(.bold)
            Text("  advertising: \(multipeer.isAdvertising ? "✅" : "❌")")
            Text("  browsing:   \(multipeer.isBrowsing ? "✅" : "❌")")
            Text("  nearby:     \(multipeer.nearbyPeers.count)")
            ForEach(multipeer.nearbyPeers, id: \.self) { p in
                Text("    • \(p.displayName)")
            }
            Text("  connected:  \(multipeer.connectedPeers.count)")
            ForEach(multipeer.connectedPeers, id: \.self) { p in
                Text("    • \(p.displayName) 🟢")
            }
            if let err = multipeer.pairingError {
                Text("  error: \(err)").foregroundStyle(.red)
            }
        }
    }

    private var webrtcSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("🔗 WEBRTC").fontWeight(.bold)
            Text("  local: \(localRiderID)")
            if webRTC.peers.isEmpty {
                Text("  peers: nenhum").foregroundStyle(.secondary)
            } else {
                ForEach(Array(webRTC.peers.keys.sorted()), id: \.self) { id in
                    let state = webRTC.peers[id] ?? .failed
                    Text("  \(id): \(stateIcon(state)) \(state.rawValue)")
                        .foregroundStyle(stateColor(state))
                }
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("📍 GPS").fontWeight(.bold)
            let auth = location.authorizationStatus
            Text("  permissao: \(authLabel(auth))")
            Text("  atualizando: \(location.isUpdating ? "✅" : "❌")")
            if let loc = location.currentLocation {
                Text("  coord: \(String(format: "%.5f", loc.coordinate.latitude)), \(String(format: "%.5f", loc.coordinate.longitude))")
                let age = Int(Date().timeIntervalSince(loc.timestamp))
                Text("  ultimo fix: \(age)s atras")
                    .foregroundStyle(age > 10 ? .red : .secondary)
            } else {
                Text("  coord: --").foregroundStyle(.red)
            }
            if let err = location.error {
                Text("  error: \(err)").foregroundStyle(.red)
            }
        }
    }

    private var turnSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("🔑 TURN/STUN").fontWeight(.bold)
            Text("  STUN: \(TURNConfig.stunURLs.count) servers")
            Text("  TURN user: \(TURNConfig.turnUsername.isEmpty ? "❌ vazio" : "✅ presente")")
            Text("  TURN cred: \(TURNConfig.turnCredential.isEmpty ? "❌ vazio" : "✅ presente")")
        }
    }

    // MARK: - Helpers

    private var statusDot: Color {
        let hasMC = !multipeer.connectedPeers.isEmpty
        let hasWebRTC = webRTC.peers.values.contains(.connected)
        if hasWebRTC { return .green }
        if hasMC { return .yellow }
        if multipeer.isAdvertising { return .orange }
        return .gray
    }

    private func stateIcon(_ s: WebRTCService.PeerState) -> String {
        switch s { case .connecting: "🟡"; case .connected: "🟢"; case .failed: "🔴" }
    }

    private func stateColor(_ s: WebRTCService.PeerState) -> Color {
        switch s { case .connecting: .orange; case .connected: .green; case .failed: .red }
    }

    private func authLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "❓ nao perguntado"
        case .restricted: "🚫 restrito"
        case .denied: "🔴 negado"
        case .authorizedWhenInUse: "✅ em uso"
        case .authorizedAlways: "✅ sempre"
        @unknown default: "?"
        }
    }
}

#Preview {
    DebugOverlay(
        multipeer: MultipeerService(),
        webRTC: WebRTCService(localRiderID: "test"),
        location: LocationService(),
        localRiderID: "rider-123"
    )
}
