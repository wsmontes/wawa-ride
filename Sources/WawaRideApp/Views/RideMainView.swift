import SwiftUI

/// Main ride view — full-screen map with HUD overlay for mesh status.
struct RideMainView: View {
    @EnvironmentObject var app: WawaAppState

    var body: some View {
        ZStack {
            // Full-screen map
            RideMapView(
                riders: $app.riders,
                routeCoords: $app.routeCoords
            )
            .ignoresSafeArea()

            // HUD overlay
            VStack {
                Spacer()
                HStack {
                    // Connection indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(app.mesh.connectedPeerCount > 0 ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text("\(app.mesh.connectedPeerCount)")
                            .font(.system(.headline, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    // Start/Stop
                    Button(action: {
                        if app.mesh.isRunning { app.stop() } else { app.start() }
                    }) {
                        Label(
                            app.mesh.isRunning ? "Stop" : "Start",
                            systemImage: app.mesh.isRunning ? "stop.circle.fill" : "play.circle.fill"
                        )
                        .font(.title2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}
