import Foundation
import Observation

/// One line of the raw transcript with its origin, so the log panel can
/// highlight error output without dropping anything from the copyable text.
struct LogLine: Equatable, Sendable {
    let text: String
    let isFromStderr: Bool
}

/// Presentation state and intents of the cleanup screen.
///
/// The view model owns UI state and orchestrates services; it knows nothing
/// about processes, pipes or the script output format.
@Observable
@MainActor
final class CleanupViewModel {
    private(set) var modules: [CleanupModule] = []
    private(set) var selectedModuleIDs: Set<String> = []
    private(set) var logLines: [LogLine] = []
    private(set) var runState: CleanupRunState = .idle
    /// `true` when the last analysis did not run to completion, so the visible
    /// module list may be missing entries.
    private(set) var isAnalysisPartial = false
    /// Human-readable classification of the last finished run (or launch
    /// failure); `nil` while idle/running and cleared when a new run starts.
    private(set) var lastIssue: CleanupRunIssue?

    @ObservationIgnored private let scriptRunner: CleanupScriptRunning
    @ObservationIgnored private let outputParser: CleanupOutputParsing
    @ObservationIgnored private let clipboard: ClipboardWriting
    @ObservationIgnored private let startsAnalysisAutomatically: Bool
    @ObservationIgnored private var hasStarted = false
    /// Incremented on every run so lines and results of an older, still
    /// delivering run are ignored after a new one has begun.
    @ObservationIgnored private var runGeneration = 0
    /// stderr lines of the current run, kept for issue classification.
    @ObservationIgnored private var stderrLines: [String] = []

    init(
        scriptRunner: CleanupScriptRunning,
        outputParser: CleanupOutputParsing,
        clipboard: ClipboardWriting,
        startsAnalysisAutomatically: Bool = true
    ) {
        self.scriptRunner = scriptRunner
        self.outputParser = outputParser
        self.clipboard = clipboard
        self.startsAnalysisAutomatically = startsAnalysisAutomatically
    }

    // MARK: - Derived state

    /// The complete transcript — every stdout and stderr line — as plain text,
    /// for the Copy button and for tests.
    var logOutput: String {
        logLines.reduce(into: "") { $0 += $1.text + "\n" }
    }

    var isBusy: Bool {
        runState.isRunning
    }

    var isAnalyzing: Bool {
        runState.activeMode == .analyze
    }

    var lastExitCode: Int32? {
        runState.exitCode
    }

    var canClean: Bool {
        !isBusy && !isAnalysisPartial && !selectedModuleIDs.isEmpty
    }

    var selectedSizeBytes: Int64 {
        modules
            .filter { selectedModuleIDs.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    var confirmationMessage: String {
        let list = modules
            .filter { selectedModuleIDs.contains($0.id) }
            .map { "• \($0.displayName) — \($0.sizeBytes.byteCountFormatted)" }
            .joined(separator: "\n")

        return String(
            localized: """
            The following will be cleaned:
            \(list)

            This action cannot be undone. Continue?
            """
        )
    }

    // MARK: - Intents

    /// Starts the initial analysis exactly once per app session.
    func startIfNeeded() {
        guard startsAnalysisAutomatically else { return }
        guard !hasStarted else { return }
        hasStarted = true
        analyze()
    }

    func analyze() {
        run(mode: .analyze, moduleIDs: CleanupModuleCatalog.allIDs)
    }

    func cleanSelected() {
        let orderedSelection = modules
            .map(\.id)
            .filter { selectedModuleIDs.contains($0) }
        guard !orderedSelection.isEmpty else { return }
        run(mode: .execute, moduleIDs: orderedSelection)
    }

    func cancel() {
        guard runState.isRunning else { return }
        log(String(localized: ">>> Cancellation: SIGTERM sent…"))
        scriptRunner.cancel()
    }

    func setSelected(_ isSelected: Bool, for moduleID: String) {
        if isSelected {
            selectedModuleIDs.insert(moduleID)
        } else {
            selectedModuleIDs.remove(moduleID)
        }
    }

    func copyLog() {
        clipboard.copy(logOutput)
    }

    // MARK: - Run lifecycle

    private func run(mode: CleanupMode, moduleIDs: [String]) {
        guard !runState.isRunning else { return }

        prepareSession(clearModules: mode == .analyze)
        runState = .running(mode)
        runGeneration += 1
        let generation = runGeneration

        do {
            try scriptRunner.run(
                mode: mode,
                moduleIDs: moduleIDs,
                onLine: { [weak self] line, stream in
                    guard let self, self.runGeneration == generation else { return }
                    self.handle(line, from: stream)
                },
                onFinish: { [weak self] result in
                    guard let self, self.runGeneration == generation else { return }
                    self.finish(result, mode: mode)
                }
            )
        } catch {
            runState = .idle
            if mode == .analyze {
                // Nothing was scanned, so whatever is on screen cannot be trusted.
                isAnalysisPartial = true
            }
            log("")
            if error is ScriptLocationError {
                log(String(localized: "Error: \(error.localizedDescription)"))
            } else {
                log(String(localized: "Failed to launch the process: \(error.localizedDescription)"))
            }
            lastIssue = .launchFailed(message: error.localizedDescription)
        }
    }

    private func finish(_ result: CleanupRunResult, mode: CleanupMode) {
        lastIssue = CleanupRunIssue.classify(
            exitCode: result.exitCode,
            wasCancelled: result.wasCancelled,
            wasTimedOut: result.wasTimedOut,
            wasInterruptedBySignal: result.wasInterruptedBySignal,
            stderrLines: stderrLines
        )

        runState = .finished(
            mode: mode,
            exitCode: result.exitCode,
            wasCancelled: result.wasCancelled
        )

        if mode == .analyze {
            // A cancelled or failed analysis stops mid-way: the partial module
            // list must not be offered for cleaning.
            isAnalysisPartial = result.wasCancelled || result.exitCode != 0
        }

        log("")
        if result.wasInterruptedBySignal {
            log(String(localized: ">>> The process was interrupted by a signal (code \(Int(result.exitCode)))."))
        } else {
            log(String(localized: ">>> The process finished. Exit code: \(Int(result.exitCode))"))
        }

        // A successful cleanup is followed by a fresh analysis so the sizes
        // on screen reflect the new state.
        if mode == .execute, result.exitCode == 0, !result.wasCancelled {
            analyze()
        }
    }

    // MARK: - Output handling

    private func handle(_ line: String, from stream: CleanupOutputStream) {
        if stream == .stderr {
            stderrLines.append(line)
        }

        switch outputParser.event(for: line) {
        case .log(let text):
            log(text, from: stream)
        case .module(let module):
            upsert(module)
        case .done, .ignored:
            break
        }
    }

    private func upsert(_ module: CleanupModule) {
        if let index = modules.firstIndex(where: { $0.id == module.id }) {
            modules[index] = module
            return
        }

        modules.append(module)
        if CleanupModuleCatalog.isSelectedByDefault(module.id) {
            selectedModuleIDs.insert(module.id)
        }
    }

    // MARK: - Session state

    /// A new analysis starts from a clean module list. A cleanup keeps the
    /// current list visible (and recoverable if the user cancels).
    private func prepareSession(clearModules: Bool) {
        if clearModules {
            modules = []
            selectedModuleIDs = []
            isAnalysisPartial = false
        }
        logLines = []
        stderrLines = []
        lastIssue = nil
    }

    private func log(_ text: String, from stream: CleanupOutputStream = .stdout) {
        logLines.append(LogLine(text: text, isFromStderr: stream == .stderr))
    }
}
