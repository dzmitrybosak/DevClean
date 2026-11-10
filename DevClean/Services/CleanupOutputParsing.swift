import Foundation

/// A parsed line of the cleanup script output.
enum CleanupScriptEvent: Equatable {
    case log(String)
    case module(CleanupModule)
    case done
    case ignored
}

protocol CleanupOutputParsing {
    func event(for line: String) -> CleanupScriptEvent
}

/// Turns raw script output into domain events.
///
/// The script reports each module with `@@MODULE|id|name|bytes` and finishes
/// with `@@DONE`. Service lines never reach the log.
struct CleanupOutputParser: CleanupOutputParsing {
    private static let modulePrefix = "@@MODULE|"

    func event(for line: String) -> CleanupScriptEvent {
        guard line.hasPrefix("@@") else {
            return .log(line)
        }

        guard line.hasPrefix(Self.modulePrefix) else {
            return line == "@@DONE" ? .done : .ignored
        }

        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 4,
              parts[0] == "@@MODULE",
              let sizeBytes = Int64(parts[parts.count - 1])
        else {
            return .ignored
        }

        // The size is always the last field, so a name may itself contain pipes.
        let name = parts[2..<(parts.count - 1)].joined(separator: "|")

        return .module(
            CleanupModule(
                id: String(parts[1]),
                name: Self.sanitized(name),
                sizeBytes: sizeBytes
            )
        )
    }

    /// Display names come from process output, so strip control characters and
    /// cap the length to keep the UI readable.
    private static func sanitized(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(scalars).prefix(120))
    }
}
