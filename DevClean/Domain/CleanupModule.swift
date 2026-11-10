import Foundation

/// One cleanup module reported by the script via `@@MODULE|id|name|bytes`.
struct CleanupModule: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int64
}

extension CleanupModule {
    /// Localized name for display; falls back to the name reported by the
    /// script for identifiers the catalog does not know yet.
    var displayName: String {
        CleanupModuleCatalog.all
            .first { $0.id == id }?
            .localizedName ?? name
    }
}
