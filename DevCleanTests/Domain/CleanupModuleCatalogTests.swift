import Foundation
import Testing

@testable import DevClean

struct CleanupModuleCatalogTests {
    @Test func containsExpectedModules() {
        #expect(CleanupModuleCatalog.all.count == 9)
        #expect(CleanupModuleCatalog.allIDs == [
            "xcode",
            "xcode-archives",
            "xcode-simulators",
            "swiftpm",
            "cocoapods",
            "carthage",
            "packages",
            "ai",
            "docker",
        ])
    }

    @Test func identifiersAreUnique() {
        let ids = CleanupModuleCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func onlyRiskyModulesAreOptOut() {
        let optOut = CleanupModuleCatalog.all
            .filter { !$0.isSelectedByDefault }
            .map(\.id)
        #expect(Set(optOut) == ["xcode-archives", "xcode-simulators", "docker"])
    }

    @Test func lookupMatchesDefinitions() {
        for definition in CleanupModuleCatalog.all {
            #expect(
                CleanupModuleCatalog.isSelectedByDefault(definition.id) == definition.isSelectedByDefault
            )
        }
        #expect(CleanupModuleCatalog.isSelectedByDefault("brand-new-module"))
    }
}
