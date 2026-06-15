import SwiftUI

@main
struct WawaRideApp: App {
    @StateObject private var session = RideSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
