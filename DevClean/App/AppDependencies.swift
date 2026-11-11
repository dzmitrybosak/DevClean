import Foundation

/// Composition root: builds the live object graph and lets Preview inject
/// lightweight fakes without touching the rest of the app.
@MainActor
struct AppDependencies {
    let outputParser: CleanupOutputParsing
    let clipboard: ClipboardWriting
    let makeScriptRunner: () -> CleanupScriptRunning
    /// Tests and previews must not spawn an analysis just by appearing.
    let startsAnalysisAutomatically: Bool

    static let live = AppDependencies(
        outputParser: CleanupOutputParser(),
        clipboard: PasteboardClipboard(),
        makeScriptRunner: {
            ProcessCleanupScriptRunner(scriptLocator: BundleScriptLocator())
        },
        startsAnalysisAutomatically: !ProcessInfo.processInfo.isRunningTests
    )

    #if DEBUG
    /// Preview graph that never spawns a real process.
    static let preview = AppDependencies(
        outputParser: CleanupOutputParser(),
        clipboard: PasteboardClipboard(),
        makeScriptRunner: { PreviewScriptRunner() },
        startsAnalysisAutomatically: false
    )
    #endif

    func makeCleanupViewModel() -> CleanupViewModel {
        CleanupViewModel(
            scriptRunner: makeScriptRunner(),
            outputParser: outputParser,
            clipboard: clipboard,
            startsAnalysisAutomatically: startsAnalysisAutomatically
        )
    }
}

#if DEBUG
@MainActor
private class PreviewScriptRunner: CleanupScriptRunning {
    func run(
        mode: CleanupMode,
        moduleIDs: [String],
        onLine: @escaping @MainActor (String, CleanupOutputStream) -> Void,
        onFinish: @escaping @MainActor (CleanupRunResult) -> Void
    ) throws {
        onFinish(
            CleanupRunResult(
                exitCode: 0,
                terminationReason: .exit,
                wasCancelled: false
            )
        )
    }

    func cancel() {}
}
#endif
