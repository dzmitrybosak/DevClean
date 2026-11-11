import Foundation

/// Static description of a module known to the cleanup script.
struct CleanupModuleDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Localized variant of `name` shown in the UI; `nil` keeps `name`.
    let localizedName: String?
    let isSelectedByDefault: Bool

    init(
        id: String,
        name: String,
        localizedName: String? = nil,
        isSelectedByDefault: Bool = true
    ) {
        self.id = id
        self.name = name
        self.localizedName = localizedName
        self.isSelectedByDefault = isSelectedByDefault
    }
}

/// Single source of truth for the modules the app knows about.
///
/// The order is meaningful: analysis results are presented in this order.
/// Keep the identifiers in sync with `clean-dev-cache.sh`.
enum CleanupModuleCatalog {
    /// Emulator data is not a cache: the module is opt-in, and the UI warns
    /// about irreversible deletion when it is selected.
    static let androidAVDModuleID = "android-avd"

    static let all: [CleanupModuleDefinition] = [
        CleanupModuleDefinition(id: "xcode", name: "Xcode & iOS", localizedName: String(localized: "Xcode & iOS")),
        // Archives are useful for symbolication and erasing simulators destroys
        // their data, so both modules are opt-in.
        CleanupModuleDefinition(id: "xcode-archives", name: "Xcode Archives", localizedName: String(localized: "Xcode Archives"), isSelectedByDefault: false),
        CleanupModuleDefinition(id: "xcode-simulators", name: "Simulator data (erase all)", localizedName: String(localized: "Simulator data (erase all)"), isSelectedByDefault: false),
        CleanupModuleDefinition(id: "swiftpm", name: "SwiftPM", localizedName: String(localized: "SwiftPM")),
        CleanupModuleDefinition(id: "cocoapods", name: "CocoaPods", localizedName: String(localized: "CocoaPods")),
        CleanupModuleDefinition(id: "carthage", name: "Carthage", localizedName: String(localized: "Carthage")),
        CleanupModuleDefinition(id: "packages", name: "Package managers", localizedName: String(localized: "Package managers")),
        CleanupModuleDefinition(id: "ai", name: "AI agents", localizedName: String(localized: "AI agents")),
        // Android Studio caches are safe to regenerate; emulator data is not a
        // cache and is therefore a separate, opt-in module.
        CleanupModuleDefinition(id: "android", name: "Android Studio", localizedName: String(localized: "Android Studio")),
        CleanupModuleDefinition(id: CleanupModuleCatalog.androidAVDModuleID, name: "Android Emulators (AVD)", localizedName: String(localized: "Android Emulators (AVD)"), isSelectedByDefault: false),
        CleanupModuleDefinition(id: "docker", name: "Docker", localizedName: String(localized: "Docker"), isSelectedByDefault: false),
    ]

    static let allIDs: [String] = all.map(\.id)

    /// Unknown identifiers are selected by default so that a newly added
    /// script module still shows up checked.
    static func isSelectedByDefault(_ moduleID: String) -> Bool {
        all.first { $0.id == moduleID }?.isSelectedByDefault ?? true
    }
}
