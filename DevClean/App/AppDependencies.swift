import Foundation

/// Composition root: builds the live object graph and lets Preview inject
/// lightweight fakes without touching the rest of the app.
@MainActor
struct AppDependencies {
    let outputParser: CleanupOutputParsing
    let clipboard: ClipboardWriting
    let makeScriptRunner: () -> CleanupScriptRunning

    static let live = AppDependencies(
        outputParser: CleanupOutputParser(),
        clipboard: PasteboardClipboard(),
        makeScriptRunner: {
            ProcessCleanupScriptRunner(scriptLocator: BundleScriptLocator())
        }
    )

    #if DEBUG
    /// Preview graph that never spawns a real process.
    static let preview = AppDependencies(
        outputParser: CleanupOutputParser(),
        clipboard: PasteboardClipboard(),
        makeScriptRunner: { PreviewScriptRunner() }
    )
    #endif

    func makeCleanupViewModel() -> CleanupViewModel {
        CleanupViewModel(
            scriptRunner: makeScriptRunner(),
            outputParser: outputParser,
            clipboard: clipboard
        )
    }
}

#if DEBUG
@MainActor
private class PreviewScriptRunner: CleanupScriptRunning {
    func run(
        mode: CleanupMode,
        moduleIDs: [String],
        onLine: @escaping @MainActor (String) -> Void,
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
