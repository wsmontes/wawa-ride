import SwiftUI

struct RideMainView: View {
    @ObservedObject var state: RideState

    var body: some View {
        ZStack {
            RideMapView(riders: $state.riders, routeCoords: $state.routeCoords)
                .ignoresSafeArea()

            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.connectedPeerCount > 0 ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text("\(state.connectedPeerCount)")
                            .font(.system(.headline, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    Button(action: { state.stopRide() }) {
                        Label("End", systemImage: "stop.circle.fill")
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
