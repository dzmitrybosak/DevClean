import Foundation

/// Result of one finished script run.
struct CleanupRunResult: Sendable {
    let exitCode: Int32
    let terminationReason: Process.TerminationReason
    let wasCancelled: Bool
    /// `true` when the run hit the runner's hard timeout and was stopped
    /// by it, rather than by the user or a crash.
    let wasTimedOut: Bool

    init(
        exitCode: Int32,
        terminationReason: Process.TerminationReason,
        wasCancelled: Bool,
        wasTimedOut: Bool = false
    ) {
        self.exitCode = exitCode
        self.terminationReason = terminationReason
        self.wasCancelled = wasCancelled
        self.wasTimedOut = wasTimedOut
    }

    var wasInterruptedBySignal: Bool {
        terminationReason == .uncaughtSignal
    }
}

/// Finite state of the cleanup script instead of independent flags, so
/// impossible combinations cannot be represented.
enum CleanupRunState: Equatable, Sendable {
    case idle
    case running(CleanupMode)
    case finished(mode: CleanupMode, exitCode: Int32, wasCancelled: Bool)

    var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    var activeMode: CleanupMode? {
        if case .running(let mode) = self { mode } else { nil }
    }

    var exitCode: Int32? {
        if case .finished(_, let exitCode, _) = self { exitCode } else { nil }
    }
}
