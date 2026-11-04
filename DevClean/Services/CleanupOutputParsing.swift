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

        let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == "@@MODULE",
              let sizeBytes = Int64(parts[3])
        else {
            return .ignored
        }

        return .module(
            CleanupModule(
                id: String(parts[1]),
                name: String(parts[2]),
                sizeBytes: sizeBytes
            )
        )
    }
}
