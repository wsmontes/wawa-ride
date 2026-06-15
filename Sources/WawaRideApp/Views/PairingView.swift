import SwiftUI
import WawaMesh

/// Pairing view: shows a PIN to share with the group, or enter leader's PIN to join.
///
/// Group formation pattern inspired by Delta Chat's SecureJoin protocol:
/// https://securejoin.readthedocs.io/
///
/// Delta Chat approach:
/// 1. Inviter generates QR with fingerprint + INVITENUMBER + AUTH secret
/// 2. Joiner scans → mutual key verification → group admission
///
/// Wawa Ride simplified version (MVP):
/// 1. Leader generates 4-digit PIN (displayed large for easy reading with helmet)
/// 2. Followers enter PIN manually or scan QR (phase 2)
/// 3. PIN is broadcast via mesh (.groupControl packet)
/// 4. Peers with matching PIN are accepted into the ride group
///
/// Phase 2 will add proper group key agreement:
/// - QR code contains: groupId (UUID) + shared secret (32 bytes) + creator pubkey
/// - Based on pattern from Delta Chat + Berty's Wesh protocol
/// - Reference: https://github.com/berty/berty (Wesh group creation)
///
/// UX considerations for motorcycle use:
/// - Large font for PIN (readable at arm's length, with gloves)
/// - Minimal interaction (one tap to start, one field to enter PIN)
/// - Visual peer count feedback (confirms devices are connecting)
struct PairingView: View {
    @EnvironmentObject var session: RideSession
    @State private var inputPIN = ""
    @State private var showingInput = false

    var body: some View {
        VStack(spacing: 28) {
            Text("Pareamento")
                .font(.title2.bold())

            // Own PIN display (large, monospaced for easy reading)
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

            // Mesh status indicator
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text("\(session.mesh.ble.connectedPeerCount) dispositivos encontrados")
                    .font(.subheadline)
            }

            Divider()

            // Enter peer's PIN to join their group
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
