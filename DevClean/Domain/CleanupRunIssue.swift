import Foundation

/// The output stream a script line came from.
///
/// stdout and stderr are read through independent pipes; keeping the origin
/// lets the UI highlight error output without losing it from the raw log.
enum CleanupOutputStream: Sendable {
    case stdout
    case stderr
}

/// Classified outcome of the most recent run, phrased for people rather than
/// for a terminal: the status label in the actions row is built from this.
enum CleanupRunIssue: Equatable, Sendable {
    case success
    case cancelled
    /// The script reported `N operation(s) failed` on stderr.
    case partialFailure(count: Int)
    case failed(exitCode: Int32)
    case timeout
    case interruptedBySignal(code: Int32)
    /// The process could not be started at all (missing script, POSIX error…).
    case launchFailed(message: String)

    /// Short status text for the label next to the actions.
    var label: String {
        switch self {
        case .success:
            String(localized: "Success")
        case .cancelled:
            String(localized: "Cancelled")
        case .partialFailure(let count):
            String(localized: "\(count) operation(s) failed")
        case .failed(let exitCode):
            String(localized: "Failed — exit code \(exitCode)")
        case .timeout:
            String(localized: "Timed out — process stopped")
        case .interruptedBySignal(let code):
            String(localized: "Interrupted by signal \(code)")
        case .launchFailed:
            String(localized: "Could not start the script")
        }
    }

    /// Actionable advice shown as the label's tooltip.
    var recoverySuggestion: String? {
        switch self {
        case .success:
            nil
        case .cancelled:
            String(localized: "The run was stopped on request. Start it again when ready.")
        case .partialFailure:
            String(localized: "Some operations did not complete. Check the highlighted lines in the log, then run the action again.")
        case .failed:
            String(localized: "Check the highlighted lines in the log for the cause.")
        case .timeout:
            String(localized: "The process ran too long and was stopped. Try cleaning fewer modules at a time.")
        case .interruptedBySignal:
            String(localized: "The process was killed by the system. Run the action again.")
        case .launchFailed:
            String(localized: "Rebuild the project (⌘R) so the script is placed in the app bundle again.")
        }
    }

    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }

    /// Picks the most specific failure the script reported: the
    /// `>>> N operation(s) failed.` line from stderr wins over a bare exit code.
    static func classify(
        exitCode: Int32,
        wasCancelled: Bool,
        wasTimedOut: Bool,
        wasInterruptedBySignal: Bool,
        stderrLines: [String]
    ) -> CleanupRunIssue {
        if wasCancelled { return .cancelled }
        if wasTimedOut { return .timeout }
        if wasInterruptedBySignal { return .interruptedBySignal(code: exitCode) }
        if let count = failedOperationCount(in: stderrLines) {
            return .partialFailure(count: count)
        }
        if exitCode != 0 { return .failed(exitCode: exitCode) }
        return .success
    }

    /// Extracts `N` from the script's summary line, e.g.
    /// `>>> 3 operation(s) failed.`.
    static func failedOperationCount(in lines: [String]) -> Int? {
        for line in lines {
            guard let range = line.range(of: ">>> "),
                  let suffixRange = line.range(of: " operation(s) failed") else { continue }
            guard suffixRange.lowerBound > range.upperBound else { continue }
            let numberPart = line[range.upperBound..<suffixRange.lowerBound]
            if let count = Int(numberPart), count > 0 {
                return count
            }
        }
        return nil
    }
}
