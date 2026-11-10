import Foundation
import Testing

@testable import DevClean

@MainActor
struct CleanupViewModelTests {
    private func makeViewModel() -> (CleanupViewModel, FakeScriptRunner, FakeClipboard) {
        let runner = FakeScriptRunner()
        let clipboard = FakeClipboard()
        let viewModel = CleanupViewModel(
            scriptRunner: runner,
            outputParser: CleanupOutputParser(),
            clipboard: clipboard
        )
        return (viewModel, runner, clipboard)
    }

    // MARK: - Analysis

    @Test func analyzeRunsAllModulesAndClearsState() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()

        #expect(runner.invocations == [
            FakeScriptRunner.Invocation(mode: .analyze, moduleIDs: CleanupModuleCatalog.allIDs)
        ])
        #expect(viewModel.modules.isEmpty)
        #expect(viewModel.runState.isRunning)
    }

    @Test func startIfNeededRunsOnlyOnce() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.startIfNeeded()
        viewModel.startIfNeeded()

        #expect(runner.invocations.count == 1)
    }

    @Test func analyzeIsIgnoredWhileRunning() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        viewModel.analyze()

        #expect(runner.invocations.count == 1)
    }

    // MARK: - Output handling

    @Test func upsertsModulesWithoutDuplicates() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()

        runner.emit("@@MODULE|xcode|Xcode & iOS|100")
        runner.emit("@@MODULE|swiftpm|SwiftPM|200")
        runner.emit("@@MODULE|xcode|Xcode & iOS|300")

        #expect(viewModel.modules.map(\.id) == ["xcode", "swiftpm"])
        #expect(viewModel.modules.map(\.sizeBytes) == [300, 200])
    }

    @Test func selectsSafeModulesAndSkipsRiskyOnes() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()

        runner.emit("@@MODULE|xcode|Xcode & iOS|1")
        runner.emit("@@MODULE|xcode-archives|Archives|1")
        runner.emit("@@MODULE|xcode-simulators|Simulators|1")
        runner.emit("@@MODULE|docker|Docker|1")
        runner.emit("@@MODULE|ai|AI agents|1")
        runner.emit("@@MODULE|future|Future module|1")

        #expect(viewModel.selectedModuleIDs == ["xcode", "ai", "future"])
    }

    @Test func logReceivesPlainLines() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()

        runner.emit("hello")
        runner.emit("world")

        #expect(viewModel.logOutput == "hello\nworld\n")
    }

    @Test func controlLinesNeverReachTheLog() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()

        runner.emit("@@MODULE|ai|AI agents|1")
        runner.emit("@@DONE")
        runner.emit("@@SOMETHING|else")

        #expect(viewModel.logOutput.isEmpty)
    }

    // MARK: - Cleanup selection

    @Test func cleanSelectedUsesOnlySelectedModulesInDisplayOrder() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|swiftpm|SwiftPM|1")
        runner.emit("@@MODULE|xcode|Xcode & iOS|1")
        runner.emit("@@MODULE|ai|AI agents|1")
        runner.finish(exitCode: 0)

        viewModel.setSelected(false, for: "xcode")
        viewModel.cleanSelected()

        #expect(runner.invocations.last == FakeScriptRunner.Invocation(
            mode: .execute,
            moduleIDs: ["swiftpm", "ai"]
        ))
    }

    @Test func cleanSelectedDoesNothingWithoutSelection() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|docker|Docker|1")
        runner.finish(exitCode: 0)

        viewModel.cleanSelected()

        #expect(runner.invocations.count == 1)
    }

    @Test func canCleanReflectsSelectionAndBusyState() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        #expect(!viewModel.canClean)

        runner.emit("@@MODULE|ai|AI agents|1")
        runner.finish(exitCode: 0)
        #expect(viewModel.canClean)

        viewModel.cleanSelected()
        #expect(!viewModel.canClean)
    }

    // MARK: - Run lifecycle

    @Test func successfulCleanupTriggersFreshAnalysis() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|ai|AI agents|1")
        runner.finish(exitCode: 0)
        viewModel.cleanSelected()

        runner.finish(exitCode: 0)

        #expect(runner.invocations.map(\.mode) == [.analyze, .execute, .analyze])
        #expect(viewModel.runState.activeMode == .analyze)
    }

    @Test func failedCleanupDoesNotReanalyze() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|ai|AI agents|1")
        runner.finish(exitCode: 0)
        viewModel.cleanSelected()

        runner.finish(exitCode: 1)

        #expect(runner.invocations.map(\.mode) == [.analyze, .execute])
        #expect(viewModel.lastExitCode == 1)
        // The list stays visible so the user can retry without re-analyzing.
        #expect(viewModel.modules.map(\.id) == ["ai"])
        #expect(viewModel.selectedModuleIDs == ["ai"])
    }

    @Test func cancelledCleanupDoesNotReanalyze() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|ai|AI agents|1")
        runner.finish(exitCode: 0)
        viewModel.cleanSelected()

        runner.finish(exitCode: 15, reason: .uncaughtSignal, wasCancelled: true)

        #expect(runner.invocations.map(\.mode) == [.analyze, .execute])
        #expect(viewModel.logOutput.contains("interrupted by a signal"))
        #expect(viewModel.modules.map(\.id) == ["ai"])
        #expect(viewModel.selectedModuleIDs == ["ai"])
    }

    @Test func cancelDelegatesToRunnerAndLogs() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()

        viewModel.cancel()

        #expect(runner.cancelCallCount == 1)
        #expect(viewModel.logOutput.contains("Cancellation"))
    }

    @Test func cancelIsIgnoredWhenIdle() {
        let (viewModel, runner, _) = makeViewModel()

        viewModel.cancel()

        #expect(runner.cancelCallCount == 0)
    }

    @Test func launchErrorReturnsToIdleAndLogs() {
        let (viewModel, runner, _) = makeViewModel()
        runner.runError = ScriptLocationError.missingFromBundle(name: "clean-dev-cache", fileExtension: "sh")

        viewModel.analyze()

        #expect(viewModel.runState == .idle)
        #expect(viewModel.logOutput.contains("Error:"))
    }

    @Test func genericLaunchErrorLogsFailureMessage() {
        let (viewModel, runner, _) = makeViewModel()
        runner.runError = NSError(domain: "test", code: 1)

        viewModel.analyze()

        #expect(viewModel.runState == .idle)
        #expect(viewModel.logOutput.contains("Failed to launch"))
    }

    // MARK: - Clipboard

    @Test func copyLogWritesCurrentLog() {
        let (viewModel, runner, clipboard) = makeViewModel()
        viewModel.analyze()
        runner.emit("line one")
        runner.emit("line two")

        viewModel.copyLog()

        #expect(clipboard.copied == ["line one\nline two\n"])
    }

    @Test func selectedSizeSumsOnlySelectedModules() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|xcode|Xcode & iOS|1000")
        runner.emit("@@MODULE|docker|Docker|900")
        runner.emit("@@MODULE|ai|AI agents|24")

        #expect(viewModel.selectedSizeBytes == 1024)
    }

    @Test func confirmationMessageListsOnlySelectedModules() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|xcode|Xcode & iOS|2048")
        runner.emit("@@MODULE|docker|Docker|4096")

        let message = viewModel.confirmationMessage

        // Only data from the module list is asserted: the surrounding text is
        // localized and must not make this test locale-dependent. Module names
        // are localized on the display side too, so the expectation goes
        // through the same lookup.
        #expect(!message.isEmpty)
        #expect(message.contains(String(localized: "Xcode & iOS")))
        #expect(message.contains(Int64(2048).byteCountFormatted))
        #expect(!message.contains("Docker"))
    }

    // MARK: - Partial analysis

    @Test func cancelledAnalysisBlocksCleaningUntilRescanned() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|ai|AI agents|1")

        runner.finish(exitCode: 15, reason: .uncaughtSignal, wasCancelled: true)

        #expect(viewModel.isAnalysisPartial)
        #expect(!viewModel.canClean)
        // The partial list stays visible…
        #expect(viewModel.modules.map(\.id) == ["ai"])

        // …until a fresh analysis starts, which resets the flag.
        viewModel.analyze()
        #expect(!viewModel.isAnalysisPartial)
        #expect(viewModel.modules.isEmpty)
    }

    @Test func failedAnalysisBlocksCleaning() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        runner.emit("@@MODULE|ai|AI agents|1")

        runner.finish(exitCode: 1)

        #expect(viewModel.isAnalysisPartial)
        #expect(!viewModel.canClean)
    }

    @Test func launchErrorDuringAnalysisMarksResultsPartial() {
        let (viewModel, runner, _) = makeViewModel()
        runner.runError = ScriptLocationError.missingFromBundle(name: "clean-dev-cache", fileExtension: "sh")

        viewModel.analyze()

        #expect(viewModel.isAnalysisPartial)
        #expect(!viewModel.canClean)
    }

    @Test func linesArrivingAfterANewRunStartedAreIgnored() {
        let (viewModel, runner, _) = makeViewModel()
        viewModel.analyze()
        let staleHandler = runner.currentLineHandler()

        // Finish the analysis, start a cleanup, then deliver a line that
        // belongs to the first (already finished) run.
        runner.emit("@@MODULE|ai|AI agents|1")
        runner.finish(exitCode: 0)
        viewModel.cleanSelected()
        staleHandler?("stale line")

        #expect(!viewModel.logOutput.contains("stale line"))
    }
}
