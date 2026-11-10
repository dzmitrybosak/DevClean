import Foundation

/// Result of running the cleanup script in an isolated environment.
struct ScriptResult {
    struct EmittedModule: Equatable {
        let id: String
        let name: String
    }

    let status: Int32
    let stdout: String
    let stderr: String

    /// Modules reported through the `@@MODULE|id|name|bytes` protocol.
    var modules: [EmittedModule] {
        stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 4, parts[0] == "@@MODULE" else { return nil }
            let name = parts[2..<(parts.count - 1)].joined(separator: "|")
            return EmittedModule(id: String(parts[1]), name: name)
        }
    }

    var moduleIDs: [String] {
        modules.map(\.id)
    }

    var lastMeaningfulLine: String? {
        stdout.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }
}

/// Runs the script with a fake `HOME`, a custom `PATH` and captured output.
func runScript(
    _ script: URL,
    arguments: [String],
    home: String,
    pathPrefix: [URL] = [],
    extraEnvironment: [String: String] = [:]
) throws -> ScriptResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path] + arguments

    var environment: [String: String] = [
        "HOME": home,
        "PATH": (pathPrefix.map(\.path) + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .joined(separator: ":"),
        "LANG": "en_US.UTF-8",
        "TMPDIR": NSTemporaryDirectory(),
    ]
    environment.merge(extraEnvironment) { _, new in new }
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    if !home.isEmpty {
        process.currentDirectoryURL = URL(fileURLWithPath: home, isDirectory: true)
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return ScriptResult(
        status: process.terminationStatus,
        stdout: String(decoding: stdout, as: UTF8.self),
        stderr: String(decoding: stderr, as: UTF8.self)
    )
}

/// Writes an executable shell stub that optionally logs its arguments and
/// exits with the requested status.
func makeShim(
    named name: String,
    in bin: URL,
    loggingTo log: URL? = nil,
    exitCode: Int = 0
) throws {
    var body = "#!/bin/sh\n"
    if let log {
        body += "printf '%s\\n' \"$*\" >> \"\(log.path)\"\n"
    }
    body += "exit \(exitCode)\n"

    let url = bin.appendingPathComponent(name)
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
}
