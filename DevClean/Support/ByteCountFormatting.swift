import Foundation

extension Int64 {
    /// Human-readable file size used across the UI.
    var byteCountFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
