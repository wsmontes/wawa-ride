import SwiftUI

struct WaitingView: View {
    @ObservedObject var state: RideState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(state.rideName)
                .font(.headline)
                .foregroundColor(.secondary)

            Text(state.pin)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
                .padding(.vertical, 8)

            Text("PIN do passeio")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text("Aguardando riders...")
                    .foregroundColor(.red)
            }

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "person.fill")
                    Text("\(state.connectedPeerCount) rider(s) conectado(s)")
                }
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("BLE advertising ativo")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Button(action: { state.startRide() }) {
                Text(state.connectedPeerCount > 0
                     ? "Partiu! (\(state.connectedPeerCount) riders)"
                     : "Iniciar Solo")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Button(action: { state.cancelRide() }) {
                Text("Cancelar")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}
