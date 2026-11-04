import SwiftUI

@main
struct DevCleanApp: App {
    @State private var viewModel = AppDependencies.live.makeCleanupViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 860, height: 780)
        .windowResizability(.contentMinSize)
    }
}
