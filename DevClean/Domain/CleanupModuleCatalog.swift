import Foundation

/// Static description of a module known to the cleanup script.
struct CleanupModuleDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isSelectedByDefault: Bool

    init(id: String, name: String, isSelectedByDefault: Bool = true) {
        self.id = id
        self.name = name
        self.isSelectedByDefault = isSelectedByDefault
    }
}

/// Single source of truth for the modules the app knows about.
///
/// The order is meaningful: analysis results are presented in this order.
/// Keep the identifiers in sync with `clean-dev-cache.sh`.
enum CleanupModuleCatalog {
    static let all: [CleanupModuleDefinition] = [
        CleanupModuleDefinition(id: "xcode", name: "Xcode & iOS"),
        // Archives are useful for symbolication and erasing simulators destroys
        // their data, so both modules are opt-in.
        CleanupModuleDefinition(id: "xcode-archives", name: "Xcode Archives", isSelectedByDefault: false),
        CleanupModuleDefinition(id: "xcode-simulators", name: "Simulator data (erase all)", isSelectedByDefault: false),
        CleanupModuleDefinition(id: "swiftpm", name: "SwiftPM"),
        CleanupModuleDefinition(id: "cocoapods", name: "CocoaPods"),
        CleanupModuleDefinition(id: "carthage", name: "Carthage"),
        CleanupModuleDefinition(id: "packages", name: "Package managers"),
        CleanupModuleDefinition(id: "ai", name: "AI agents"),
        CleanupModuleDefinition(id: "docker", name: "Docker"),
    ]

    static let allIDs: [String] = all.map(\.id)

    /// Unknown identifiers are selected by default so that a newly added
    /// script module still shows up checked.
    static func isSelectedByDefault(_ moduleID: String) -> Bool {
        all.first { $0.id == moduleID }?.isSelectedByDefault ?? true
    }
}
