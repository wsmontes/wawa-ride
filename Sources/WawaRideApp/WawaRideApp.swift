import SwiftUI

@main
struct WawaRideApp: App {
    @StateObject private var state = RideState()

    var body: some Scene {
        WindowGroup {
            switch state.phase {
            case .idle, .creating:
                CreateRideView(state: state)
            case .proposed:
                WaitingView(state: state)
            case .active:
                RideMainView(state: state)
            case .completed:
                CreateRideView(state: state)
            }
        }
    }
}
