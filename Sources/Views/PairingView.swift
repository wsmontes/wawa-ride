import SwiftUI
import MultipeerConnectivity

// MARK: - Pairing State

enum PairingState {
    case idle
    case searching
    case foundPeers
    case peerConnecting
    case connected
}

struct PairingView: View {
    @ObservedObject var multipeer: MultipeerService
    let errorMessage: String?
    let onStartRide: () -> Void

    @State private var rotationAngle: Double = 0
    @State private var pulseScale: Double = 1.0

    private var state: PairingState {
        if !multipeer.connectedPeers.isEmpty {
            return .connected
        }
        if multipeer.isAdvertising {
            if !multipeer.nearbyPeers.isEmpty {
                return .foundPeers
            }
            return .searching
        }
        return .idle
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: - Hero Section
                heroSection

                Spacer().frame(height: 24)

                // MARK: - Status Card
                statusCard
                    .padding(.horizontal, 24)

                Spacer().frame(height: 24)

                // MARK: - Peers List
                if state == .foundPeers || state == .connected {
                    peersList
                        .padding(.horizontal, 24)
                }

                Spacer()

                // MARK: - Action Buttons
                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Radar rings when searching
            ZStack {
                // Pulse rings
                if state == .searching {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(.orange.opacity(0.3), lineWidth: 2)
                            .frame(width: 100, height: 100)
                            .scaleEffect(pulseScale + CGFloat(i) * 0.3)
                            .opacity(2.0 - pulseScale - CGFloat(i) * 0.3)
                    }
                }

                // Motorcycle icon
                Circle()
                    .fill(state == .connected ? Color.green : Color.orange)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "motorcycle")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .rotationEffect(.degrees(state == .searching ? -10 : 0))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.2
                }
            }

            Text("Wawa Ride")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Status Card

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundStyle(statusColor)
                .symbolEffect(.bounce, options: .repeat(.periodic(delay: 1)), isActive: state == .searching)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state == .searching {
                ProgressView()
                    .tint(.orange)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Peers List

    @ViewBuilder
    private var peersList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dispositivos proximos")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ScrollView {
                VStack(spacing: 6) {
                    // Found peers (not yet connected)
                    ForEach(multipeer.nearbyPeers, id: \.self) { peer in
                        peerRow(peer: peer, isConnected: false)
                    }

                    // Connected peers
                    ForEach(multipeer.connectedPeers, id: \.self) { peer in
                        peerRow(peer: peer, isConnected: true)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private func peerRow(peer: MCPeerID, isConnected: Bool) -> some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(isConnected ? Color.green : Color.yellow)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "motorcycle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(isConnected ? "Conectado via Bluetooth" : "Disponivel para parear")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                Label("Conectado", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button {
                    multipeer.invite(peer: peer)
                } label: {
                    Text("Convidar")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            // Start Ride — only when peers connected
            if !multipeer.connectedPeers.isEmpty {
                Button(action: onStartRide) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Iniciar Passeio")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
            }

            // Force re-pair
            if !multipeer.isAdvertising || !multipeer.isBrowsing {
                Button {
                    multipeer.startPairing()
                } label: {
                    Label("Forcar Reconexao", systemImage: "arrow.trianglehead.clockwise")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
    }

    // MARK: - Dynamic Content

    private var statusIcon: String {
        switch state {
        case .idle:       return "antenna.radiowaves.left.and.right"
        case .searching:  return "dot.radiowaves.left.and.right"
        case .foundPeers: return "person.2.wave.2"
        case .connected:  return "checkmark.shield"
        case .peerConnecting: return "arrow.trianglehead.merge"
        }
    }

    private var statusColor: Color {
        switch state {
        case .idle:       return .secondary
        case .searching:  return .orange
        case .foundPeers: return .yellow
        case .peerConnecting: return .blue
        case .connected:  return .green
        }
    }

    private var statusTitle: String {
        switch state {
        case .idle:       return "Pronto para parear"
        case .searching:  return "Procurando motociclistas..."
        case .foundPeers: return "Motociclistas encontrados!"
        case .peerConnecting: return "Conectando..."
        case .connected:  return "Pareado com sucesso!"
        }
    }

    private var statusSubtitle: String {
        switch state {
        case .idle:       return "Toque no botao abaixo para comecar"
        case .searching:  return "Seu iPhone esta visivel via Bluetooth e Wi-Fi"
        case .foundPeers: return "Convide os dispositivos abaixo para parear"
        case .peerConnecting: return "Estabelecendo conexao segura..."
        case .connected:  return "\(multipeer.connectedPeers.count) motociclista(s) conectado(s). Pronto para o passeio!"
        }
    }

    private var statusText: String {
        switch state {
        case .idle:       return ""
        case .searching:  return "Aproxime os iPhones para facilitar o pareamento"
        case .foundPeers: return ""
        case .peerConnecting: return ""
        case .connected:  return ""
        }
    }
}

// MARK: - Preview

#Preview {
    PairingView(
        multipeer: MultipeerService(),
        errorMessage: nil,
        onStartRide: {}
    )
}
