import Foundation

enum CleanupMode: String, Sendable {
    case analyze
    case execute

    var progressTitle: String {
        switch self {
        case .analyze: String(localized: "Analyzing…")
        case .execute: String(localized: "Cleaning…")
        }
    }
}
