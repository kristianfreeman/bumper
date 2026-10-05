import Foundation
import Testing
@testable import AppCore

struct SubtitleFinderTests {
    /// Checked against an independent implementation (Python's struct.unpack '<Q').
    @Test func hashesLikeOpenSubtitles() {
        var head = Data(count: OpenSubtitlesHash.chunk)
        var tail = Data(count: OpenSubtitlesHash.chunk)
        for i in 0..<head.count { head[i] = UInt8(i % 251) }
        for i in 0..<tail.count { tail[i] = UInt8((i * 7) % 253) }
        #expect(OpenSubtitlesHash.compute(size: 1_234_567_890, head: head, tail: tail) == Self.reference)
        #expect(OpenSubtitlesHash.compute(size: 10, head: Data(count: 10), tail: Data(count: 10)) == nil)   // too small to hash
    }

    static let reference = "db8b3deff4f3f618"
}
