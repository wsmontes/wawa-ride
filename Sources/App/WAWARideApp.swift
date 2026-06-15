import SwiftUI

@main
struct WAWARideApp: App {
    init() {
        // Initialize services early — not dependent on view lifecycle
        let vm = AppServices.shared.viewModel
        vm.onAppLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Global service locator to ensure ViewModel survives view lifecycle changes.
@MainActor
final class AppServices {
    static let shared = AppServices()
    let viewModel = RideViewModel()
}
