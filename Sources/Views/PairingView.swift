import SwiftUI
import MultipeerConnectivity

struct PairingView: View {
    let multipeer: MultipeerService
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

                Text(multipeer.isAdvertising || multipeer.isBrowsing
                     ? "Procurando motociclistas..."
                     : "Pronto para parear")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Nearby Peers
            if !multipeer.nearbyPeers.isEmpty || !multipeer.connectedPeers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dispositivos próximos")
                        .font(.headline)

                    ForEach(multipeer.nearbyPeers, id: \.self) { peer in
                        HStack {
                            Circle()
                                .fill(.yellow)
                                .frame(width: 10, height: 10)
                            Text(peer.displayName)
                            Spacer()
                            Button("Convidar") {
                                multipeer.invite(peer: peer)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    ForEach(multipeer.connectedPeers, id: \.self) { peer in
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 10, height: 10)
                            Text(peer.displayName)
                            Spacer()
                            Text("Conectado")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            // Action Button
            VStack(spacing: 16) {
                if !multipeer.connectedPeers.isEmpty {
                    Button(action: onStartRide) {
                        Label("Iniciar Passeio", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button {
                    if multipeer.isAdvertising {
                        multipeer.stopPairing()
                    } else {
                        multipeer.startPairing()
                    }
                } label: {
                    Label(
                        multipeer.isAdvertising ? "Parar Pareamento" : "Começar Pareamento",
                        systemImage: multipeer.isAdvertising ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
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
}

#Preview {
    PairingView(
        multipeer: MultipeerService(),
        onStartRide: {}
    )
}
