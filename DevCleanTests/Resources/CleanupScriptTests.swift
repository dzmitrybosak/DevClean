import Foundation
import Testing

@testable import DevClean

struct CleanupScriptTests {
    @Test func refusesEmptyHome() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let result = try runScript(TestPaths.cleanupScript, arguments: ["--analyze"], home: "")

        #expect(result.status == 2)
        #expect(result.stderr.contains("HOME"))
    }

    @Test func refusesRootHome() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let result = try runScript(TestPaths.cleanupScript, arguments: ["--analyze"], home: "/")

        #expect(result.status == 2)
        #expect(result.stderr.contains("HOME"))
    }

    @Test func analyzeNeverDeletesAnything() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        try temp.file("Library/Caches/org.swift.swiftpm/packages/checkout/file")
        try temp.file("Library/Caches/org.carthage.CarthageKit/build/file")

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--analyze", "--modules", "swiftpm,carthage"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(temp.exists("Library/Caches/org.swift.swiftpm/packages/checkout/file"))
        #expect(temp.exists("Library/Caches/org.carthage.CarthageKit/build/file"))
    }

    @Test func executeDeletesOnlySelectedModules() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        try temp.file("Library/Caches/org.swift.swiftpm/packages/checkout/file")
        try temp.file("Library/Caches/org.carthage.CarthageKit/build/file")

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "swiftpm"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(!temp.exists("Library/Caches/org.swift.swiftpm"))
        #expect(temp.exists("Library/Caches/org.carthage.CarthageKit/build/file"))
    }

    @Test func failingExternalCommandReturnsNonZeroExitCode() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        try temp.file("Library/Caches/CocoaPods/file")

        let bin = try temp.directory("bin")
        try makeShim(named: "pod", in: bin, exitCode: 1)

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "cocoapods"],
            home: temp.url.path,
            pathPrefix: [bin]
        )

        #expect(result.status == 1)
        #expect(result.stdout.contains("(command failed)"))
        #expect(result.stderr.contains("failed"))
    }

    @Test func unknownModuleIsIgnored() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        try temp.file("Library/Caches/org.swift.swiftpm/file")

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "not-a-module"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(result.moduleIDs.isEmpty)
        #expect(temp.exists("Library/Caches/org.swift.swiftpm/file"))
    }

    @Test func emitsProtocolInOrderAndEndsWithDone() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        try temp.file("Library/Caches/org.swift.swiftpm/file")
        try temp.file("Library/Caches/org.carthage.CarthageKit/file")

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--analyze", "--modules", "carthage,swiftpm"],
            home: temp.url.path
        )

        #expect(result.moduleIDs == ["swiftpm", "carthage"])
        #expect(result.lastMeaningfulLine == "@@DONE")
    }

    @Test(.enabled(if: geteuid() != 0))
    func failedDeletionReturnsNonZeroExitCode() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }
        defer { try? temp.setPermissions(0o755, of: "Library/Developer/Xcode") }

        try temp.file("Library/Developer/Xcode/DerivedData/some/file")
        try temp.setPermissions(0o555, of: "Library/Developer/Xcode")

        let bin = try temp.directory("bin")
        try makeShim(named: "xcrun", in: bin)

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "xcode"],
            home: temp.url.path,
            pathPrefix: [bin]
        )

        #expect(result.status == 1)
        #expect(result.stderr.contains("failed"))
        // The directory itself cannot be removed, but `rm -rf` may already have
        // emptied it — the test only verifies the failure was detected.
        #expect(temp.exists("Library/Developer/Xcode/DerivedData"))
    }

    @Test func neverDeletesTheAppBundleContainingTheScript() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }
        defer { try? temp.setPermissions(0o755, of: "Library/Developer/Xcode") }

        let derived = "Library/Developer/Xcode/DerivedData"
        try temp.file("\(derived)/Other/file.txt")
        try temp.file("\(derived)/My.app/Contents/Info.plist")
        let scriptContents = try String(contentsOf: TestPaths.cleanupScript, encoding: .utf8)
        let script = try temp.executableScript(
            "\(derived)/My.app/Contents/Resources/clean-dev-cache.sh",
            contents: scriptContents
        )

        let bin = try temp.directory("bin")
        try makeShim(named: "xcrun", in: bin)

        let result = try runScript(
            script,
            arguments: ["--execute", "--modules", "xcode"],
            home: temp.url.path,
            pathPrefix: [bin]
        )

        #expect(result.status == 0)
        #expect(!temp.exists("\(derived)/Other"))
        #expect(temp.exists("\(derived)/My.app/Contents/Info.plist"))
        #expect(temp.exists("\(derived)/My.app/Contents/Resources/clean-dev-cache.sh"))
    }

    @Test func dockerNeverPrunesVolumesOrDeletesTheVMDisk() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let disk = "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
        try temp.file(disk, contents: "vm-data")

        let bin = try temp.directory("bin")
        let log = temp.url.appendingPathComponent("docker.log")
        try makeShim(named: "docker", in: bin, loggingTo: log)

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "docker"],
            home: temp.url.path,
            pathPrefix: [bin]
        )

        let calls = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(result.status == 0)
        #expect(calls.contains("builder prune -af"))
        #expect(calls.contains("image prune -af"))
        #expect(!calls.contains("--volumes"))
        #expect(!calls.contains("system prune"))
        #expect(temp.exists(disk))
    }

    @Test func aiDiscoveryMatchesOnlyBundleLikeNames() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        try temp.file("Library/Caches/com.xiaomi.mimo desktop/file")
        try temp.file("Library/Caches/com.mimo.code/file")
        try temp.file("Library/Caches/SomeMimoThing/file")

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--analyze", "--modules", "ai"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(result.stdout.contains("Xiaomi MiMo cache (com.xiaomi.mimo desktop)"))
        #expect(result.stdout.contains("Xiaomi MiMo cache (com.mimo.code)"))
        #expect(!result.stdout.contains("SomeMimoThing"))
    }

    @Test func missingPathsAreReportedButDoNotFail() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--analyze", "--modules", "swiftpm"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(result.stdout.contains("(not found)"))
        #expect(result.moduleIDs == ["swiftpm"])
    }
}
