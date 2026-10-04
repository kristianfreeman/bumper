@testable import Companion
import Foundation
import Testing

/// Frames survive being split anywhere (TCP delivers whatever it likes).
@Suite("Companion frames")
struct FramesTests {
    @Test func roundTripsAcrossArbitrarySplits() throws {
        let item = CompanionItem(id: "m1", title: "Endless Voyage", subtitle: "1982 · 2 h 13 min", imageURL: URL(string: "http://tv.local/i.jpg"), minutes: 133)
        let messages: [CompanionMessage] = [
            .hello(name: "Living Room", version: CompanionService.version),
            .state(CompanionState(tvName: "Living Room", focused: item, tonight: [CompanionPlanEntry(item: item, start: Date(timeIntervalSince1970: 1_800_000_000), suggested: false, overruns: false)], tonightSummary: "One thing.")),
            .command(.moveInTonight(itemId: "m1", by: -1)),
            .command(.setDoneBy(nil)),
            .results(query: "funny", items: [item], understood: "comedy"),
        ]
        let stream = try messages.map(Frames.encode).reduce(Data(), +)
        for chunk in [1, 3, 7, 64, stream.count] {
            var reader = Frames.Reader()
            var got: [CompanionMessage] = []
            var i = 0
            while i < stream.count {
                got += try reader.append(stream.subdata(in: i..<min(stream.count, i + chunk)))
                i += chunk
            }
            #expect(got == messages, "split every \(chunk) bytes")
        }
    }
}
