import Foundation

@testable import DevClean

// MARK: - Fakes

@MainActor
final class FakeScriptRunner: CleanupScriptRunning {
    struct Invocation: Equatable {
        let mode: CleanupMode
        let moduleIDs: [String]
    }

    private(set) var invocations: [Invocation] = []
    private(set) var cancelCallCount = 0
    var runError: Error?

    private var lineHandler: (@MainActor (String, CleanupOutputStream) -> Void)?
    private var finishHandler: (@MainActor (CleanupRunResult) -> Void)?

    func run(
        mode: CleanupMode,
        moduleIDs: [String],
        onLine: @escaping @MainActor (String, CleanupOutputStream) -> Void,
        onFinish: @escaping @MainActor (CleanupRunResult) -> Void
    ) throws {
        if let runError {
            throw runError
        }
        invocations.append(Invocation(mode: mode, moduleIDs: moduleIDs))
        lineHandler = onLine
        finishHandler = onFinish
    }

    func cancel() {
        cancelCallCount += 1
    }

    func emit(_ line: String, on stream: CleanupOutputStream = .stdout) {
        lineHandler?(line, stream)
    }

    /// The `onLine` handler registered by the most recent `run`, so a test can
    /// deliver a line "from another run" after a new one has started.
    func currentLineHandler() -> (@MainActor (String, CleanupOutputStream) -> Void)? {
        lineHandler
    }

    func finish(
        exitCode: Int32 = 0,
        reason: Process.TerminationReason = .exit,
        wasCancelled: Bool = false,
        wasTimedOut: Bool = false
    ) {
        let result = CleanupRunResult(
            exitCode: exitCode,
            terminationReason: reason,
            wasCancelled: wasCancelled,
            wasTimedOut: wasTimedOut
        )
        finishHandler?(result)
    }
}

@MainActor
final class FakeClipboard: ClipboardWriting {
    private(set) var copied: [String] = []

    func copy(_ text: String) {
        copied.append(text)
    }
}

struct StubScriptLocator: ScriptLocating {
    let url: URL

    func locateScript() throws -> URL {
        url
    }
}

struct ThrowingScriptLocator: ScriptLocating {
    func locateScript() throws -> URL {
        throw ScriptLocationError.missingFromBundle(name: "missing", fileExtension: "sh")
    }
}

// MARK: - Temporary sandbox

/// A throwaway directory used instead of the real home directory.
struct TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevCleanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func cleanUp() {
        // Restore write permissions in case a test made a directory read-only.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ relativePath: String) -> String {
        url.appendingPathComponent(relativePath).path
    }

    @discardableResult
    func directory(_ relativePath: String) throws -> URL {
        let directory = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    @discardableResult
    func file(_ relativePath: String, contents: String = "x") throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @discardableResult
    func executableScript(_ relativePath: String, contents: String) throws -> URL {
        let file = try self.file(relativePath, contents: contents)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: file.path
        )
        return file
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relativePath))
    }

    func setPermissions(_ permissions: Int, of relativePath: String) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: path(relativePath)
        )
    }
}

// MARK: - Repository locations

enum TestPaths {
    /// Root of the checked-out project, derived from this source file.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DevCleanTests
            .deletingLastPathComponent() // repository root
    }

    static var cleanupScript: URL {
        repositoryRoot.appendingPathComponent("DevClean/Resources/clean-dev-cache.sh")
    }
}
