import Foundation
import Testing

@testable import DevClean

struct ByteCountFormattingTests {
    /// The formatter is a thin wrapper around a locale-dependent API, so only
    /// behaviour that must hold for every locale is asserted here.
    @Test func producesDistinctHumanReadableSizes() {
        let zero = Int64(0).byteCountFormatted
        let kilobyte = Int64(1_536).byteCountFormatted
        let gigabyte = Int64(1_073_741_824).byteCountFormatted

        #expect(!zero.isEmpty)
        #expect(zero != kilobyte)
        #expect(kilobyte != gigabyte)
        #expect(gigabyte.contains { $0.isNumber })
    }
}
