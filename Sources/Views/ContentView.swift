import SwiftUI

struct ContentView: View {
    @State private var viewModel = RideViewModel()

    var body: some View {
        Group {
            if viewModel.isRideActive {
                MapView(
                    riders: viewModel.currentRiders,
                    localRiderID: viewModel.localRiderID
                )
            } else {
                PairingView(
                    multipeer: viewModel.multipeer,
                    onStartRide: { viewModel.startRide() }
                )
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.isRideActive)
    }
}

#Preview {
    ContentView()
}
