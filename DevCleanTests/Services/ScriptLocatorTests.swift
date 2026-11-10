import Foundation
import Testing

@testable import DevClean

struct ScriptLocatorTests {
    @Test func reportsMissingScriptByName() {
        let locator = BundleScriptLocator(
            bundle: .main,
            name: "definitely-not-bundled-\(UUID().uuidString)",
            fileExtension: "sh"
        )

        #expect(throws: ScriptLocationError.self) {
            try locator.locateScript()
        }
    }

    @Test func resolvesScriptFromBundleAndReportsUnavailableAfterRemoval() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let bundleURL = temp.url.appendingPathComponent("Test.bundle", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true),
            withIntermediateDirectories: true
        )
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>test.bundle</string>
        <key>CFBundlePackageType</key><string>BNDL</string>
        </dict></plist>
        """
        try infoPlist.write(
            to: bundleURL.appendingPathComponent("Contents/Info.plist"),
            atomically: true,
            encoding: .utf8
        )
        let script = bundleURL.appendingPathComponent("Contents/Resources/clean-dev-cache.sh")
        try "#!/bin/sh\n".write(to: script, atomically: true, encoding: .utf8)

        guard let bundle = Bundle(url: bundleURL) else {
            Issue.record("Could not create a test bundle at \(bundleURL.path)")
            return
        }
        let locator = BundleScriptLocator(bundle: bundle)
        #expect(try locator.locateScript() == script)

        try FileManager.default.removeItem(at: script)
        #expect(throws: ScriptLocationError.self) {
            try locator.locateScript()
        }
    }

    @Test func resolvesScriptFromTheRealAppBundle() throws {
        // The test host runs inside DevClean.app, so this verifies that the
        // script is really copied into the built bundle and stays executable.
        let locator = BundleScriptLocator(bundle: .main)

        let url = try locator.locateScript()

        #expect(url.lastPathComponent == "clean-dev-cache.sh")
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
    }
}
