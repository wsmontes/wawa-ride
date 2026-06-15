import SwiftUI
import WawaMesh

/// Pairing view: shows a PIN to share, or lets user enter a peer's PIN.
struct PairingView: View {
    @EnvironmentObject var session: RideSession
    @State private var inputPIN = ""
    @State private var showingInput = false

    var body: some View {
        VStack(spacing: 28) {
            Text("Pareamento")
                .font(.title2.bold())

            // Show own PIN
            VStack(spacing: 8) {
                Text("Seu PIN")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.pairingPIN)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .kerning(8)
                Text("Compartilhe com o grupo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            // Mesh status
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text("\(session.mesh.ble.connectedPeerCount) dispositivos encontrados")
                    .font(.subheadline)
            }

            Divider()

            // Enter peer PIN
            if showingInput {
                HStack {
                    TextField("PIN do líder", text: $inputPIN)
                        .keyboardType(.numberPad)
                        .font(.title3.monospaced())
                        .multilineTextAlignment(.center)
                        .frame(width: 140)
                        .textFieldStyle(.roundedBorder)
                    Button("Entrar") {
                        session.joinWithPIN(inputPIN)
                    }
                    .disabled(inputPIN.count != 4)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            } else {
                Button("Entrar em grupo existente") {
                    showingInput = true
                }
                .font(.subheadline)
            }

            Spacer()

            Button {
                session.confirmPairing()
            } label: {
                Label("Iniciar Passeio", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(session.mesh.ble.connectedPeerCount > 0 ? .orange : .gray,
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .disabled(session.mesh.ble.connectedPeerCount == 0)
        }
        .padding()
    }
}
