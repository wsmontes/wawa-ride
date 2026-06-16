import SwiftUI

/// Minimal BLE mesh status — temporary until map integration is complete.
struct MeshStatusView: View {
    @StateObject private var mesh = MeshService()
    @State private var message = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Wawa Ride")
                .font(.largeTitle).bold()

            Text(mesh.localPeerIDHex)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            HStack {
                Circle()
                    .fill(mesh.connectedPeerCount > 0 ? Color.green : Color.orange)
                    .frame(width: 14, height: 14)
                Text("\(mesh.connectedPeerCount) rider(s) connected")
                    .font(.headline)
            }

            HStack(spacing: 16) {
                Button("Start Mesh") { mesh.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(mesh.isRunning)
                Button("Stop") { mesh.stop() }
                    .buttonStyle(.bordered)
                    .disabled(!mesh.isRunning)
            }

            Text("Last message: \(mesh.lastMessage)")
                .font(.caption)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(8)

            HStack {
                TextField("Test message", text: $message)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    mesh.broadcastTest(message)
                    message = ""
                }
                .buttonStyle(.bordered)
                .disabled(message.isEmpty || !mesh.isRunning)
            }
            .padding(.horizontal)

            Text("MapLibre offline map ready (8 MB Victoria)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}
