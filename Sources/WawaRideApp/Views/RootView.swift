import SwiftUI
import WawaMap

struct RootView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        ZStack {
            switch session.phase {
            case .idle:
                StartView()
            case .riding, .navigating:
                RideView()
            }
        }
    }
}

struct StartView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "motorcycle")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Wawa Ride")
                .font(.largeTitle.bold())
            Text("Mesh · Offline · Livre")
                .foregroundStyle(.secondary)
            Button { session.startRide() } label: {
                Label("Iniciar Passeio", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
    }
}

struct RideView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        ZStack(alignment: .bottom) {
            RideMapView(riders: $session.riders, routeCoords: $session.routeCoords)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Peer count badge
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("\(session.mesh.ble.connectedPeerCount) peers")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())

                Button { session.stopRide() } label: {
                    Label("Encerrar", systemImage: "stop.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.bottom, 40)
        }
    }
}
