import Foundation
import Testing

@testable import DevClean

struct LineStreamReaderTests {
    /// `LineStreamReader` calls back from a background queue, so the box is
    /// lock-protected and `nonisolated` — the project defaults to
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise
    /// make `append` unreachable from the reader's `@Sendable` closure.
    private nonisolated final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ lines: [String]) {
            lock.withLock { storage.append(contentsOf: lines) }
        }

        var lines: [String] {
            lock.withLock { storage }
        }
    }

    private func makeReader() -> (pipe: Pipe, reader: LineStreamReader, collector: Collector) {
        let pipe = Pipe()
        let collector = Collector()
        let reader = LineStreamReader(handle: pipe.fileHandleForReading) {
            collector.append($0)
        }
        return (pipe, reader, collector)
    }

    private func read(_ data: Data) throws -> [String] {
        let (pipe, reader, collector) = makeReader()
        try pipe.fileHandleForWriting.write(contentsOf: data)
        reader.finish()
        return collector.lines
    }

    @Test func splitsCompleteLinesAndFlushesTail() throws {
        #expect(try read(Data("one\ntwo\nthree".utf8)) == ["one", "two", "three"])
    }

    @Test func doesNotEmitTrailingEmptyLine() throws {
        #expect(try read(Data("one\ntwo\n".utf8)) == ["one", "two"])
    }

    @Test func stripsCarriageReturn() throws {
        #expect(try read(Data("one\r\ntwo\r\n".utf8)) == ["one", "two"])
    }

    @Test func preservesMultibyteCharacters() throws {
        #expect(try read(Data("Привет\nмир".utf8)) == ["Привет", "мир"])
    }

    @Test func emptyStreamEmitsNothing() throws {
        #expect(try read(Data()) == [])
    }

    @Test func handlesLongLine() throws {
        let payload = String(repeating: "a", count: 32 * 1024)
        #expect(try read(Data("\(payload)\n".utf8)) == [payload])
    }

    @Test func finishIsIdempotent() throws {
        let (pipe, reader, collector) = makeReader()
        try pipe.fileHandleForWriting.write(contentsOf: Data("one".utf8))

        reader.finish()
        reader.finish()

        #expect(collector.lines == ["one"])
    }

    /// The reader must reassemble UTF-8 sequences and lines split across
    /// separate writes, which is what happens with real process output.
    @Test(.timeLimit(.minutes(1)))
    func streamsMultibyteInputAcrossChunks() async throws {
        let (pipe, reader, collector) = makeReader()
        reader.start()

        let payload = Data("Привет\nмир\n".utf8)
        let writer = pipe.fileHandleForWriting
        // Split inside the first multibyte character.
        try writer.write(contentsOf: payload.prefix(1))
        try await Task.sleep(for: .milliseconds(50))
        try writer.write(contentsOf: payload.dropFirst(1))
        try writer.close()

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while collector.lines.count < 2, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        reader.finish()
        #expect(collector.lines == ["Привет", "мир"])
    }
}
