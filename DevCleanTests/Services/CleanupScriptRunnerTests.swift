import Foundation
import Testing

@testable import DevClean

@MainActor
struct CleanupScriptRunnerTests {
    // MARK: - Helpers

    private func runAndWait(
        _ runner: ProcessCleanupScriptRunner,
        mode: CleanupMode = .analyze,
        moduleIDs: [String] = [],
        onLine: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> CleanupRunResult {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try runner.run(
                    mode: mode,
                    moduleIDs: moduleIDs,
                    onLine: onLine,
                    onFinish: { continuation.resume(returning: $0) }
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func makeRunner(
        scriptContents: String,
        timeout: Duration = .seconds(30)
    ) throws -> (ProcessCleanupScriptRunner, TempDirectory) {
        let temp = try TempDirectory()
        let script = try temp.executableScript("run.sh", contents: scriptContents)
        let runner = ProcessCleanupScriptRunner(
            scriptLocator: StubScriptLocator(url: script),
            timeout: timeout
        )
        return (runner, temp)
    }

    @MainActor
    private final class LineBox {
        var lines: [String] = []
    }

    private struct LineWaitTimeout: Error {
        let text: String
    }

    private func waitForLine(
        containing text: String,
        in box: LineBox,
        timeout: Duration = .seconds(5)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if box.lines.contains(where: { $0.contains(text) }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw LineWaitTimeout(text: text)
    }

    // MARK: - Security regressions

    @Test func scriptPathWithCommandSubstitutionIsNotExecuted() async throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let marker = "devclean_pwned_\(UUID().uuidString)"
        let directory = try temp.directory("evil$(touch \(marker))")
        let script = try temp.executableScript(
            "evil$(touch \(marker))/run.sh",
            contents: "#!/bin/sh\necho ok\n"
        )
        #expect(directory.path.contains("$("))

        let runner = ProcessCleanupScriptRunner(scriptLocator: StubScriptLocator(url: script))
        let result = try await runAndWait(runner)

        #expect(result.exitCode == 0)
        let markerPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(marker)
            .path
        #expect(!FileManager.default.fileExists(atPath: markerPath))
    }

    @Test func scriptPathWithQuotesAndSemicolonsIsNotExecuted() async throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let marker = "devclean_pwned_\(UUID().uuidString)"
        let directory = try temp.directory("evil\"; touch \(marker); echo \"")
        let script = try temp.executableScript(
            "evil\"; touch \(marker); echo \"/run.sh",
            contents: "#!/bin/sh\necho ok\n"
        )
        #expect(FileManager.default.fileExists(atPath: directory.path))

        let runner = ProcessCleanupScriptRunner(scriptLocator: StubScriptLocator(url: script))
        let result = try await runAndWait(runner)

        #expect(result.exitCode == 0)
        let markerPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(marker)
            .path
        #expect(!FileManager.default.fileExists(atPath: markerPath))
    }

    @Test func forwardsModeAndModuleListAsSeparateArguments() async throws {
        let (runner, temp) = try makeRunner(
            scriptContents: "#!/bin/sh\nprintf 'ARG:%s\\n' \"$@\"\n"
        )
        defer { temp.cleanUp() }

        var lines: [String] = []
        _ = try await runAndWait(
            runner,
            mode: .execute,
            moduleIDs: ["xcode", "ai"],
            onLine: { lines.append($0) }
        )

        #expect(lines == ["ARG:--execute", "ARG:--modules", "ARG:xcode,ai"])
    }

    @Test func runsScriptWithoutExecutableBit() async throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        // bash gets the path as an argument, so the bundled resource needs
        // neither an executable bit nor a working shebang.
        let script = try temp.file("run.sh", contents: "#!/bin/sh\necho ok\n")
        #expect(!FileManager.default.isExecutableFile(atPath: script.path))

        let runner = ProcessCleanupScriptRunner(scriptLocator: StubScriptLocator(url: script))
        let result = try await runAndWait(runner)

        #expect(result.exitCode == 0)
    }

    @Test func passesOnlyMinimalEnvironment() async throws {
        let (runner, temp) = try makeRunner(scriptContents: "#!/bin/sh\nenv\n")
        defer { temp.cleanUp() }

        var lines: [String] = []
        _ = try await runAndWait(runner, onLine: { lines.append($0) })

        let environment = Dictionary(
            uniqueKeysWithValues: lines.compactMap { line -> (String, String)? in
                guard let separator = line.firstIndex(of: "=") else { return nil }
                return (String(line[..<separator]), String(line[line.index(after: separator)...]))
            }
        )

        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(environment["HOME"] == NSHomeDirectory())
        #expect(environment["USER"] == NSUserName())
        #expect(environment["LANG"] == "en_US.UTF-8")
        // The test harness exports these; they must not leak into the child.
        #expect(environment["XCTestConfigurationFilePath"] == nil)
        #expect(environment["XCTestBundlePath"] == nil)
        #expect(environment["DYLD_INSERT_LIBRARIES"] == nil)
    }

    // MARK: - Lifecycle

    @Test func reportsExitCode() async throws {
        let (runner, temp) = try makeRunner(scriptContents: "#!/bin/sh\nexit 7\n")
        defer { temp.cleanUp() }

        let result = try await runAndWait(runner)

        #expect(result.exitCode == 7)
        #expect(result.terminationReason == .exit)
        #expect(!result.wasCancelled)
    }

    @Test func streamsStdoutAndStderr() async throws {
        let (runner, temp) = try makeRunner(
            scriptContents: "#!/bin/sh\necho out\necho err >&2\n"
        )
        defer { temp.cleanUp() }

        var lines: [String] = []
        _ = try await runAndWait(runner, onLine: { lines.append($0) })

        #expect(Set(lines) == ["out", "err"])
    }

    @Test func throwingLocatorPropagatesError() {
        let runner = ProcessCleanupScriptRunner(scriptLocator: ThrowingScriptLocator())

        #expect(throws: ScriptLocationError.self) {
            try runner.run(mode: .analyze, moduleIDs: [], onLine: { _ in }, onFinish: { _ in })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelStopsTheProcessAndFlagsIt() async throws {
        let (runner, temp) = try makeRunner(
            scriptContents: "#!/bin/sh\necho ready\nsleep 60\n"
        )
        defer { temp.cleanUp() }

        let box = LineBox()
        let task = Task { try await runAndWait(runner, onLine: { box.lines.append($0) }) }
        try await waitForLine(containing: "ready", in: box)
        runner.cancel()

        let result = try await task.value
        #expect(result.wasCancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutStopsTheProcess() async throws {
        let (runner, temp) = try makeRunner(
            scriptContents: "#!/bin/sh\nsleep 60\n",
            timeout: .milliseconds(300)
        )
        defer { temp.cleanUp() }

        var lines: [String] = []
        let result = try await runAndWait(runner, onLine: { lines.append($0) })

        #expect(!result.wasCancelled)
        #expect(lines.contains { $0.contains("Timeout") })
    }

    @Test(.timeLimit(.minutes(1)))
    func ignoresSecondRunWhileFirstIsActive() async throws {
        let (runner, temp) = try makeRunner(
            scriptContents: "#!/bin/sh\nsleep 0.2\n"
        )
        defer { temp.cleanUp() }

        try await confirmation("only the first run finishes", expectedCount: 1) { confirm in
            try runner.run(mode: .analyze, moduleIDs: [], onLine: { _ in }, onFinish: { _ in confirm() })
            // The guard must ignore this call instead of replacing handlers.
            try runner.run(mode: .analyze, moduleIDs: [], onLine: { _ in }, onFinish: { _ in confirm() })
            try await Task.sleep(for: .milliseconds(600))
        }
    }
}
