import SwiftUI
import MapKit

struct RideMainView: View {
    @ObservedObject var state: RideState
    @State private var showPIN = false
    @State private var isAutoCentered = true
    @State private var hasEverAutoCentered = false

    var body: some View {
        ZStack {
            SmartMapView(
                riders: $state.riders,
                routeCoords: $state.routeCoords,
                speedKmh: $state.speedKmh,
                isAutoCentered: $isAutoCentered
            )
            .ignoresSafeArea()
            .onReceive(NotificationCenter.default.publisher(for: .userDidPanMap)) { _ in
                hasEverAutoCentered = true
                isAutoCentered = false
            }

            // Top HUD
            VStack {
                HStack {
                    VStack(spacing: 0) {
                        Text(state.speedDisplay)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                        Text("km/h")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    Spacer()

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
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 16).padding(.top, 8)

                if showPIN {
                    HStack {
                        Image(systemName: "key.fill").foregroundColor(.secondary)
                        Text("PIN: \(state.pin)")
                            .font(.system(.body, design: .monospaced))
                        Text("— compartilhe").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                }

                Spacer()

                // Re-center button (appears when user manually pans)
                if !isAutoCentered && hasEverAutoCentered {
                    Button(action: {
                        NotificationCenter.default.post(name: .userDidTapReCenter, object: nil)
                        isAutoCentered = true
                    }) {
                        Label("Recentralizar", systemImage: "location.fill")
                            .font(.subheadline)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 4)
                }

                // Stop button
                Button(action: { state.stopRide() }) {
                    Label("Encerrar", systemImage: "stop.circle.fill")
                        .font(.title2)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 8)
            }

        }
        .animation(.easeInOut, value: showPIN)
        .animation(.easeInOut, value: isAutoCentered)
    }
}
