import Foundation
import Testing

@testable import DevClean

/// The module list exists twice by design: in Swift and in the shell script.
/// These tests fail if the two drift apart.
struct CatalogScriptConsistencyTests {
    @Test func scriptEmitsCatalogModulesInOrder() throws {
        let temp = try TempDirectory()
        defer { temp.cleanUp() }

        let result = try runScript(
            TestPaths.cleanupScript,
            arguments: ["--analyze"],
            home: temp.url.path
        )

        #expect(result.status == 0)
        #expect(result.modules.map(\.id) == CleanupModuleCatalog.allIDs)
        #expect(result.modules.map(\.name) == CleanupModuleCatalog.all.map(\.name))
    }
}
