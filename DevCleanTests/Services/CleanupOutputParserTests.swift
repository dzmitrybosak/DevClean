import Foundation
import Testing

@testable import DevClean

struct CleanupOutputParserTests {
    private let parser = CleanupOutputParser()

    @Test func parsesModuleLine() {
        #expect(
            parser.event(for: "@@MODULE|xcode|Xcode & iOS|1024")
                == .module(CleanupModule(id: "xcode", name: "Xcode & iOS", sizeBytes: 1024))
        )
    }

    @Test func parsesBoundarySizes() {
        #expect(
            parser.event(for: "@@MODULE|ai|AI agents|0")
                == .module(CleanupModule(id: "ai", name: "AI agents", sizeBytes: 0))
        )
        #expect(
            parser.event(for: "@@MODULE|ai|AI agents|-5")
                == .module(CleanupModule(id: "ai", name: "AI agents", sizeBytes: -5))
        )
        #expect(
            parser.event(for: "@@MODULE|packages|Packages|\(Int64.max)")
                == .module(CleanupModule(id: "packages", name: "Packages", sizeBytes: Int64.max))
        )
    }

    @Test func keepsPipesInName() {
        #expect(
            parser.event(for: "@@MODULE|id|a|b|c|42")
                == .module(CleanupModule(id: "id", name: "a|b|c", sizeBytes: 42))
        )
    }

    @Test func ignoresMalformedModuleLines() {
        #expect(parser.event(for: "@@MODULE|id|name") == .ignored)
        #expect(parser.event(for: "@@MODULE|id|name|not-a-number") == .ignored)
        #expect(parser.event(for: "@@MODULE") == .ignored)
    }

    @Test func recognizesDone() {
        #expect(parser.event(for: "@@DONE") == .done)
    }

    @Test func ignoresUnknownControlLines() {
        #expect(parser.event(for: "@@SOMETHING|else") == .ignored)
    }

    @Test func passesPlainTextToLog() {
        #expect(parser.event(for: "=== Xcode & iOS ===") == .log("=== Xcode & iOS ==="))
        #expect(parser.event(for: "") == .log(""))
    }

    @Test func stripsControlCharactersFromName() {
        let event = parser.event(for: "@@MODULE|ai|bad\u{0007}name\nhere|1")
        guard case .module(let module) = event else {
            Issue.record("Expected a module, got \(event)")
            return
        }
        #expect(module.name == "badnamehere")
    }

    @Test func capsNameLength() {
        let longName = String(repeating: "x", count: 500)
        let event = parser.event(for: "@@MODULE|long|\(longName)|1")
        guard case .module(let module) = event else {
            Issue.record("Expected a module, got \(event)")
            return
        }
        #expect(module.name.count == 120)
    }

    @Test func keepsEmptyName() {
        #expect(
            parser.event(for: "@@MODULE|id||7")
                == .module(CleanupModule(id: "id", name: "", sizeBytes: 7))
        )
    }
}
