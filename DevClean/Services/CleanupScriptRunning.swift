import Foundation

protocol CleanupScriptRunning: AnyObject {
    func run(
        mode: CleanupMode,
        moduleIDs: [String],
        onLine: @escaping @MainActor (String, CleanupOutputStream) -> Void,
        onFinish: @escaping @MainActor (CleanupRunResult) -> Void
    ) throws

    func cancel()
}

/// Runs `clean-dev-cache.sh` through `/bin/bash` and streams its output.
///
/// The app is not sandboxed, so the script can touch `~/Library` caches.
@MainActor
final class ProcessCleanupScriptRunner: CleanupScriptRunning {
    // GUI apps do not inherit the PATH from the user's shell profile.
    private static let searchPath =
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Hard limit so a hung child (`pod`, `docker`, `simctl`) cannot keep the
    /// app busy forever. The user can still cancel earlier.
    private let timeout: Duration

    private let scriptLocator: ScriptLocating

    private var process: Process?
    private var stdoutReader: LineStreamReader?
    private var stderrReader: LineStreamReader?
    private var timeoutTask: Task<Void, Never>?
    private var wasCancelled = false
    /// Set by the timeout task before it signals the process, so the result
    /// can distinguish a timeout from a user cancellation or a crash.
    private var wasTimedOut = false

    init(
        scriptLocator: ScriptLocating,
        timeout: Duration = .seconds(30 * 60)
    ) {
        self.scriptLocator = scriptLocator
        self.timeout = timeout
    }

    func run(
        mode: CleanupMode,
        moduleIDs: [String],
        onLine: @escaping @MainActor (String, CleanupOutputStream) -> Void,
        onFinish: @escaping @MainActor (CleanupRunResult) -> Void
    ) throws {
        guard process == nil else { return }

        let scriptURL = try scriptLocator.locateScript()
        wasCancelled = false
        wasTimedOut = false

        let process = Process()

        // Run the script as bash's own argument list: no intermediate shell
        // parses the command, so a bundle living in a directory whose name
        // contains `"`, `$()` or backticks can never become executable code.
        // It also means neither the executable bit nor the shebang of the
        // bundled resource matters — the test harness invokes it the same way.
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        var arguments = [scriptURL.path]
        arguments.append(mode == .execute ? "--execute" : "--analyze")
        arguments.append("--modules")
        arguments.append(moduleIDs.joined(separator: ","))
        process.arguments = arguments

        // Pass a minimal environment: the inherited one may carry tokens,
        // DYLD_* overrides or CI secrets that the child does not need.
        process.environment = [
            "PATH": Self.searchPath,
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LANG": "en_US.UTF-8",
            "TMPDIR": NSTemporaryDirectory(),
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let stdoutReader = makeReader(for: stdoutPipe.fileHandleForReading, stream: .stdout, onLine: onLine)
        let stderrReader = makeReader(for: stderrPipe.fileHandleForReading, stream: .stderr, onLine: onLine)

        self.process = process
        self.stdoutReader = stdoutReader
        self.stderrReader = stderrReader

        stdoutReader.start()
        stderrReader.start()

        process.terminationHandler = { [weak self] finishedProcess in
            // Drain the tails of both pipes before reporting the exit code.
            let tailLines = stdoutReader.finish().map { ($0, CleanupOutputStream.stdout) }
                + stderrReader.finish().map { ($0, CleanupOutputStream.stderr) }

            let status = finishedProcess.terminationStatus
            let reason = finishedProcess.terminationReason

            Task { @MainActor [weak self] in
                guard let self else { return }
                // The tail is delivered in the same MainActor turn as the
                // completion callback, so the last lines can never be appended
                // to the log of the run that follows this one.
                for (line, stream) in tailLines {
                    onLine(line, stream)
                }
                let result = CleanupRunResult(
                    exitCode: status,
                    terminationReason: reason,
                    wasCancelled: self.wasCancelled,
                    wasTimedOut: self.wasTimedOut
                )
                self.resetProcess()
                onFinish(result)
            }
        }

        do {
            try process.run()
        } catch {
            _ = stdoutReader.finish()
            _ = stderrReader.finish()
            resetProcess()
            throw error
        }

        startTimeout(for: process, onLine: onLine)
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        wasCancelled = true
        signalProcess(process, SIGTERM)

        // Escalate if the script (or a child holding the process alive) ignores
        // SIGTERM, so the UI does not stay stuck in the running state.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.process === process, process.isRunning else { return }
            self.signalProcess(process, SIGKILL)
        }
    }

    private func startTimeout(
        for process: Process,
        onLine: @escaping @MainActor (String, CleanupOutputStream) -> Void
    ) {
        // Captured by value: the closure must not reach for `self` before the
        // `weak` capture is resolved (and the value never changes anyway).
        let timeout = self.timeout
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, self.process === process, process.isRunning else { return }
            self.wasTimedOut = true
            onLine(String(localized: ">>> Timeout: stopping the process…"), .stderr)
            self.signalProcess(process, SIGTERM)
            try? await Task.sleep(for: .seconds(3))
            if self.process === process, process.isRunning {
                self.signalProcess(process, SIGKILL)
            }
        }
    }

    /// Signals the child, and its whole process group when it leads one.
    ///
    /// A negative PID is only used after confirming that the child is a group
    /// leader — otherwise `kill(-pid)` could signal this app's own group.
    private func signalProcess(_ process: Process, _ signal: Int32) {
        let pid = process.processIdentifier
        if getpgid(pid) == pid {
            kill(-pid, signal)
        } else {
            kill(pid, signal)
        }
    }

    private func makeReader(
        for handle: FileHandle,
        stream: CleanupOutputStream,
        onLine: @escaping @MainActor (String, CleanupOutputStream) -> Void
    ) -> LineStreamReader {
        LineStreamReader(handle: handle) { lines in
            Task { @MainActor in
                for line in lines {
                    onLine(line, stream)
                }
            }
        }
    }

    private func resetProcess() {
        timeoutTask?.cancel()
        timeoutTask = nil
        process = nil
        stdoutReader = nil
        stderrReader = nil
    }
}
