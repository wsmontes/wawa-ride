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

                // Ride overlay — stop button + peer status
                VStack {
                    HStack {
                        // Peer count pill
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
            } else {
                PairingView(
                    multipeer: viewModel.multipeer,
                    errorMessage: viewModel.errorMessage,
                    onStartRide: { viewModel.startRide() }
                )
            }

            // Error overlay
            if let error = viewModel.errorMessage {
                VStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                viewModel.errorMessage = nil
                            }
                        }
                    Spacer()
                }
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.isRideActive)
    }
}

#Preview {
    ContentView()
}
