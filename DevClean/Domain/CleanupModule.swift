import Foundation

/// One cleanup module reported by the script via `@@MODULE|id|name|bytes`.
struct CleanupModule: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int64
}
