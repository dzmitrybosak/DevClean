import Foundation
import Testing

@testable import DevClean

struct CleanupRunStateTests {
    @Test func stateReflectsRunLifecycle() {
        let idle = CleanupRunState.idle
        #expect(!idle.isRunning)
        #expect(idle.activeMode == nil)
        #expect(idle.exitCode == nil)

        let running = CleanupRunState.running(.execute)
        #expect(running.isRunning)
        #expect(running.activeMode == .execute)
        #expect(running.exitCode == nil)

        let finished = CleanupRunState.finished(mode: .analyze, exitCode: 3, wasCancelled: true)
        #expect(!finished.isRunning)
        #expect(finished.activeMode == nil)
        #expect(finished.exitCode == 3)
    }

    @Test func runResultReportsSignals() {
        let signal = CleanupRunResult(
            exitCode: 15,
            terminationReason: .uncaughtSignal,
            wasCancelled: true
        )
        #expect(signal.wasInterruptedBySignal)

        let normal = CleanupRunResult(
            exitCode: 0,
            terminationReason: .exit,
            wasCancelled: false
        )
        #expect(!normal.wasInterruptedBySignal)
    }
}
