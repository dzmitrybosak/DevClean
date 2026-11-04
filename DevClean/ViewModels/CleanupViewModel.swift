import Foundation
import Observation

/// Presentation state and intents of the cleanup screen.
///
/// The view model owns UI state and orchestrates services; it knows nothing
/// about processes, pipes or the script output format.
@Observable
@MainActor
final class CleanupViewModel {
    private(set) var modules: [CleanupModule] = []
    private(set) var selectedModuleIDs: Set<String> = []
    private(set) var logOutput = ""
    private(set) var runState: CleanupRunState = .idle

    @ObservationIgnored private let scriptRunner: CleanupScriptRunning
    @ObservationIgnored private let outputParser: CleanupOutputParsing
    @ObservationIgnored private let clipboard: ClipboardWriting
    @ObservationIgnored private var hasStarted = false

    init(
        scriptRunner: CleanupScriptRunning,
        outputParser: CleanupOutputParsing,
        clipboard: ClipboardWriting
    ) {
        self.scriptRunner = scriptRunner
        self.outputParser = outputParser
        self.clipboard = clipboard
    }

    // MARK: - Derived state

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
        !isBusy && !selectedModuleIDs.isEmpty
    }

    var selectedSizeBytes: Int64 {
        modules
            .filter { selectedModuleIDs.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    var confirmationMessage: String {
        let list = modules
            .filter { selectedModuleIDs.contains($0.id) }
            .map { "• \($0.name) — \($0.sizeBytes.byteCountFormatted)" }
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

        do {
            try scriptRunner.run(
                mode: mode,
                moduleIDs: moduleIDs,
                onLine: { [weak self] line in
                    self?.handle(line)
                },
                onFinish: { [weak self] result in
                    self?.finish(result, mode: mode)
                }
            )
        } catch {
            runState = .idle
            log("")
            if error is ScriptLocationError {
                log(String(localized: "Error: \(error.localizedDescription)"))
            } else {
                log(String(localized: "Failed to launch the process: \(error.localizedDescription)"))
            }
        }
    }

    private func finish(_ result: CleanupRunResult, mode: CleanupMode) {
        runState = .finished(
            mode: mode,
            exitCode: result.exitCode,
            wasCancelled: result.wasCancelled
        )

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

    private func handle(_ line: String) {
        switch outputParser.event(for: line) {
        case .log(let text):
            log(text)
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
        }
        logOutput = ""
        runState = .idle
    }

    private func log(_ text: String) {
        logOutput.append(text)
        logOutput.append("\n")
    }
}
