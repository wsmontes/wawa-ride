import SwiftUI

struct ContentView: View {
    @State private var viewModel = RideViewModel()

    var body: some View {
        ZStack {
            if viewModel.isRideActive {
                MapView(
                    riders: viewModel.currentRiders,
                    localRiderID: viewModel.localRiderID
                )
                .ignoresSafeArea()
                .zIndex(0)

                // Top bar
                VStack {
                    HStack {
                        Text("\(viewModel.multipeer.connectedPeers.count) conectado(s)")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        Button(action: { viewModel.stopRide() }) {
                            Label("Parar", systemImage: "xmark")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    Spacer()
                }
                .zIndex(1)
            } else {
                PairingView(
                    multipeer: viewModel.multipeer,
                    errorMessage: viewModel.errorMessage,
                    onStartRide: { viewModel.startRide() }
                )
                .zIndex(0)
            }

            // Error toast
            if let error = viewModel.errorMessage {
                VStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
                .padding(.top, 60)
                .zIndex(2)
            }

            // Debug overlay — top-left
            VStack {
                HStack {
                    DebugOverlay(
                        multipeer: viewModel.multipeer,
                        webRTC: viewModel.webRTC,
                        location: viewModel.locationService,
                        localRiderID: viewModel.localRiderID
                    )
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 50)
            .padding(.leading, 8)
            .zIndex(3)
        }
    }
}

#Preview {
    ContentView()
}
