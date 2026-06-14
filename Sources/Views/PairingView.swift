import SwiftUI
import MultipeerConnectivity

struct PairingView: View {
    let multipeer: MultipeerService
    let errorMessage: String?
    let onStartRide: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon + Status
            VStack(spacing: 12) {
                Image(systemName: "motorcycle")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("Wawa Ride")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Nearby Peers list
            if !multipeer.nearbyPeers.isEmpty || !multipeer.connectedPeers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dispositivos proximos")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(multipeer.nearbyPeers, id: \.self) { peer in
                                peerRow(peer: peer, isConnected: false)
                            }
                            ForEach(multipeer.connectedPeers, id: \.self) { peer in
                                peerRow(peer: peer, isConnected: true)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }
                .padding(.horizontal)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                // Start Ride button — only visible when peers connected
                if !multipeer.connectedPeers.isEmpty {
                    Button(action: onStartRide) {
                        Label("Iniciar Passeio", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // Pairing toggle
                Button {
                    if multipeer.isAdvertising {
                        multipeer.stopPairing()
                    } else {
                        multipeer.startPairing()
                    }
                } label: {
                    Label(
                        multipeer.isAdvertising ? "Parar Pareamento" : "Comecar Pareamento",
                        systemImage: multipeer.isAdvertising
                            ? "antenna.radiowaves.left.and.right.slash"
                            : "antenna.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    private var statusText: String {
        if multipeer.isAdvertising {
            return "Procurando motociclistas..."
        } else if !multipeer.connectedPeers.isEmpty {
            return "\(multipeer.connectedPeers.count) motociclista(s) conectado(s)"
        } else {
            return "Pronto para parear"
        }
    }

    private func peerRow(peer: MCPeerID, isConnected: Bool) -> some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.yellow)
                .frame(width: 10, height: 10)
            Text(peer.displayName)
            Spacer()
            if isConnected {
                Text("Conectado")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Convidar") {
                    multipeer.invite(peer: peer)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    PairingView(
        multipeer: MultipeerService(),
        errorMessage: nil,
        onStartRide: {}
    )
}
