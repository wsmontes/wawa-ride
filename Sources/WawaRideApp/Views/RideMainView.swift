import SwiftUI

struct RideMainView: View {
    @ObservedObject var state: RideState
    @State private var showPIN = false

    var body: some View {
        ZStack {
            // Full-screen map
            RideMapView(riders: $state.riders, routeCoords: $state.routeCoords)
                .ignoresSafeArea()

            // Top bar — speed + rider count
            VStack {
                HStack {
                    // Speed
                    VStack(spacing: 0) {
                        Text(state.currentSpeed)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                        Text("km/h")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    Spacer()

                    // Riders + PIN
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(state.connectedPeerCount > 0 ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text("\(state.connectedPeerCount)")
                                .font(.system(.headline, design: .monospaced))
                        }
                        Button(action: { showPIN.toggle() }) {
                            Text(showPIN ? state.pin : "PIN")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if showPIN {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.secondary)
                        Text("PIN: \(state.pin)")
                            .font(.system(.body, design: .monospaced))
                        Text("— compartilhe com outros riders")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Bottom — stop button
                Button(action: { state.stopRide() }) {
                    Label("Encerrar", systemImage: "stop.circle.fill")
                        .font(.title2)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 8)
            }
        }
        .animation(.easeInOut, value: showPIN)
    }
}
