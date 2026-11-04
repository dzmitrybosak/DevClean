import Foundation

/// Result of one finished script run.
struct CleanupRunResult: Sendable {
    let exitCode: Int32
    let terminationReason: Process.TerminationReason
    let wasCancelled: Bool

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
