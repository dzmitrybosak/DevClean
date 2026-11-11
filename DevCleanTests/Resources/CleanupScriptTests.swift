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
        // The VM disk is never measured: pruning does not shrink it, so the
        // log must not promise a reclaimable size.
        #expect(result.stdout.contains("(no size)"))
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

    // MARK: - Android

    @Test func androidModuleCoversIDECachesLogsAndGradle() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let caches = [
            "Library/Caches/Google/AndroidStudio2024.1/file",
            "Library/Caches/AndroidStudio2023.3/file",
            "Library/Caches/JetBrains/AndroidStudio2022.2/file",
        ]
        let logs = "Library/Logs/Google/AndroidStudio2024.1/file"
        let gradle = [".gradle/caches/file", ".gradle/wrapper/dists/file"]
        let androidCaches = [".android/cache/file", ".android/build-cache/file"]
        for path in caches + [logs] + gradle + androidCaches {
            try temp.file(path)
        }

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "android"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(result.moduleIDs == ["android"])
        // Version-specific directory names are discovered through globs.
        #expect(result.stdout.contains("IDE cache (AndroidStudio2024.1)"))
        #expect(result.stdout.contains("IDE cache (AndroidStudio2023.3)"))
        #expect(result.stdout.contains("IDE cache (AndroidStudio2022.2)"))
        #expect(result.stdout.contains("IDE logs (AndroidStudio2024.1)"))
        // The module size is the sum of every cleaned path, not just the last one.
        let moduleLine = result.stdout
            .split(separator: "\n")
            .first { $0.hasPrefix("@@MODULE|android|") }
        let reportedBytes = moduleLine.flatMap { Int($0.split(separator: "|").last ?? "") }
        #expect((reportedBytes ?? 0) > 0)
        for path in caches + [logs] + gradle + androidCaches {
            #expect(!temp.exists(path))
        }
    }

    @Test func androidModuleKeepsSettingsWorkingFilesAndAVD() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let protected = [
            "Library/Application Support/Google/AndroidStudio2024.1/options/settings.xml",
            ".android/avd/Pixel_API_35.avd/userdata.img",
            ".gradle/daemon/8.9/daemon.log",
            ".gradle/native/libfoo.dylib",
        ]
        for path in protected {
            try temp.file(path)
        }
        try temp.file("Library/Caches/Google/AndroidStudio2024.1/file")

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "android"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(!temp.exists("Library/Caches/Google/AndroidStudio2024.1/file"))
        for path in protected {
            #expect(temp.exists(path), "android must not delete \(path)")
        }
    }

    @Test func androidAVDIsDeletedOnlyWhenSelectedExplicitly() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let avd = ".android/avd/Pixel_API_35.avd/userdata.img"
        let cache = "Library/Caches/Google/AndroidStudio2024.1/file"
        try temp.file(avd)
        try temp.file(cache)

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "android-avd"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(result.moduleIDs == ["android-avd"])
        #expect(result.stdout.contains("DESTRUCTIVE"))
        #expect(!temp.exists(avd))
        // Selecting only the AVD module must not touch IDE caches.
        #expect(temp.exists(cache))
    }

    @Test func androidIsShownEvenWhenNothingIsInstalled() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--analyze", "--modules", "android,android-avd"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(result.moduleIDs == ["android", "android-avd"])
        // Every covered path is listed, including glob families with no match.
        #expect(result.stdout.contains("IDE cache (Google/AndroidStudio*)"))
        #expect(result.stdout.contains("IDE cache (AndroidStudio*)"))
        #expect(result.stdout.contains("IDE cache (JetBrains/AndroidStudio*)"))
        #expect(result.stdout.contains("IDE logs (Google/AndroidStudio*)"))
        #expect(result.stdout.contains("Gradle caches"))
        #expect(result.stdout.contains("Gradle wrapper dists"))
        #expect(result.stdout.contains("Android cache"))
        #expect(result.stdout.contains("Android build-cache"))
        #expect(result.stdout.contains("Android AVD data"))
        #expect(result.stdout.contains("(not found)"))
    }

    @Test func packagesNoLongerCleansGradleCaches() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        try temp.file(".gradle/caches/file")
        try temp.file("Library/Caches/Homebrew/file")

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--execute", "--modules", "packages"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(!temp.exists("Library/Caches/Homebrew/file"))
        // Gradle caches moved to the `android` module, so `packages` must leave
        // them alone and must not mention them in its output.
        #expect(temp.exists(".gradle/caches/file"))
        #expect(!result.stdout.contains("gradle caches"))
    }
}
