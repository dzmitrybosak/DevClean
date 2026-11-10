import Foundation

extension ProcessInfo {
    /// True when the code runs inside an XCTest/Swift Testing host.
    ///
    /// The app-hosted test bundle launches the real app, whose SwiftUI window
    /// would otherwise trigger the automatic analysis against the user's home.
    var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
