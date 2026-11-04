import Foundation

protocol CleanupScriptRunning: AnyObject {
    func run(
        mode: CleanupMode,
        moduleIDs: [String],
        onLine: @escaping @MainActor (String) -> Void,
        onFinish: @escaping @MainActor (CleanupRunResult) -> Void
    ) throws

    func cancel()
}

/// Runs `clean-dev-cache.sh` with `/bin/zsh` and streams its output.
///
/// The app is not sandboxed, so the script can touch `~/Library` caches.
@MainActor
final class ProcessCleanupScriptRunner: CleanupScriptRunning {
    // GUI apps do not inherit the PATH from the user's shell profile.
    private static let searchPath =
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private let scriptLocator: ScriptLocating

    private var process: Process?
    private var stdoutReader: LineStreamReader?
    private var stderrReader: LineStreamReader?
    private var wasCancelled = false

    init(scriptLocator: ScriptLocating) {
        self.scriptLocator = scriptLocator
    }

    func run(
        mode: CleanupMode,
        moduleIDs: [String],
        onLine: @escaping @MainActor (String) -> Void,
        onFinish: @escaping @MainActor (CleanupRunResult) -> Void
    ) throws {
        guard process == nil else { return }

        let scriptURL = try scriptLocator.locateScript()
        wasCancelled = false

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        // `"$@"` forwards each following argument as a separate positional
        // parameter, so module lists never need shell quoting.
        var arguments = ["-c", "\"\(scriptURL.path)\" \"$@\"", "devcachecleaner"]
        arguments.append(mode == .execute ? "--execute" : "--analyze")
        arguments.append("--modules")
        arguments.append(moduleIDs.joined(separator: ","))
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.searchPath
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let stdoutReader = makeReader(for: stdoutPipe.fileHandleForReading, onLine: onLine)
        let stderrReader = makeReader(for: stderrPipe.fileHandleForReading, onLine: onLine)

        self.process = process
        self.stdoutReader = stdoutReader
        self.stderrReader = stderrReader

        stdoutReader.start()
        stderrReader.start()

        process.terminationHandler = { [weak self] finishedProcess in
            // Drain the tails of both pipes before reporting the exit code.
            stdoutReader.finish()
            stderrReader.finish()

            let status = finishedProcess.terminationStatus
            let reason = finishedProcess.terminationReason

            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = CleanupRunResult(
                    exitCode: status,
                    terminationReason: reason,
                    wasCancelled: self.wasCancelled
                )
                self.resetProcess()
                onFinish(result)
            }
        }

        do {
            try process.run()
        } catch {
            stdoutReader.finish()
            stderrReader.finish()
            resetProcess()
            throw error
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        wasCancelled = true
        process.terminate()
    }

    private func makeReader(
        for handle: FileHandle,
        onLine: @escaping @MainActor (String) -> Void
    ) -> LineStreamReader {
        LineStreamReader(handle: handle) { lines in
            Task { @MainActor in
                for line in lines {
                    onLine(line)
                }
            }
        }
    }

    private func resetProcess() {
        process = nil
        stdoutReader = nil
        stderrReader = nil
    }
}
