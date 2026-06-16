import SwiftUI

/// Minimal BLE mesh connectivity test.
///
/// Shows:
/// - Local peer identity (8-byte PeerID)
/// - Connected peer count
/// - Log of received packets
/// - Broadcast test button
struct BLEConnectionView: View {
    @StateObject private var mesh = BLETestService()
    @State private var testCount = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Header
                Text("Wawa BLE Mesh Test")
                    .font(.title2).bold()

                // Local identity
                VStack(alignment: .leading, spacing: 4) {
                    Text("My PeerID:").font(.caption).foregroundColor(.secondary)
                    Text(mesh.localPeerIDHex)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Peer count
                HStack {
                    Circle()
                        .fill(mesh.connectedPeerCount > 0 ? Color.green : Color.orange)
                        .frame(width: 12, height: 12)
                    Text("\(mesh.connectedPeerCount) peer(s) connected")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: { mesh.start() }) {
                        Label("Start", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(mesh.isRunning)

                    Button(action: { mesh.stop() }) {
                        Label("Stop", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!mesh.isRunning)
                }
                .padding(.horizontal)

                Button(action: {
                    testCount += 1
                    mesh.broadcastTest("Ping #\(testCount)")
                }) {
                    Label("Broadcast Test", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!mesh.isRunning)
                .padding(.horizontal)

                // Log
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log:").font(.caption).foregroundColor(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(mesh.log.reversed(), id: \.self) { entry in
                                Text(entry)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(entry.contains("ERROR") ? .red : .primary)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
}
