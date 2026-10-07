import JellyfinAPI
import PlaybackCore
import Testing

@Suite("Chapters")
struct ChapterTests {
    static let t = BaseItem.ticksPerSecond

    /// In order, named, each keeping its server index (its image's); past
    /// the end and repeated starts left out.
    @Test func listIsOrderedNamedAndKeepsImageIndexes() {
        let t = Self.t
        let chapters = PlayerChapter.list([
            Chapter(startPositionTicks: 600 * t, name: "The Harbour", imageTag: "b"),
            Chapter(startPositionTicks: 0, name: "Arrival", imageTag: "a"),
            Chapter(startPositionTicks: 600 * t, name: "Duplicate"),
            Chapter(startPositionTicks: 1200 * t, name: "Chapter 03"),
            Chapter(startPositionTicks: 9000 * t, name: "Another cut's"),
        ], runtime: .seconds(1500))
        #expect(chapters.map(\.name) == ["Arrival", "The Harbour", "Chapter 3"])
        #expect(chapters.map(\.index) == [1, 0, 3])
        #expect(chapters.map(\.start) == [.zero, .seconds(600), .seconds(1200)])
        #expect(chapters[0].imageTag == "a" && chapters[2].imageTag == nil)
    }

    @Test func unnamedChaptersAreNumbered() {
        #expect(PlayerChapter.name(nil, number: 1) == "Chapter 1")
        #expect(PlayerChapter.name("  ", number: 2) == "Chapter 2")
        #expect(PlayerChapter.name("Chapter 07", number: 3) == "Chapter 3")
        #expect(PlayerChapter.name("chapter12", number: 4) == "Chapter 4")
        #expect(PlayerChapter.name("00:12:30.000", number: 5) == "Chapter 5")
        #expect(PlayerChapter.name("Chapter of Dreams", number: 6) == "Chapter of Dreams")
        #expect(PlayerChapter.name(" Landfall ", number: 7) == "Landfall")
    }

    @Test func currentIsTheLastToHaveStarted() {
        let chapters = [0, 60, 120].enumerated().map { PlayerChapter(index: $0, start: .seconds($1), name: "C\($0)") }
        #expect(PlayerChapter.current(in: chapters, at: .seconds(30))?.index == 0)
        #expect(PlayerChapter.current(in: chapters, at: .seconds(60))?.index == 1)
        #expect(PlayerChapter.current(in: chapters, at: .milliseconds(59_800))?.index == 1)   // a seek landing just short
        #expect(PlayerChapter.current(in: chapters, at: .seconds(500))?.index == 2)
        let late = [PlayerChapter(index: 0, start: .seconds(10), name: "Late")]
        #expect(PlayerChapter.current(in: late, at: .seconds(2)) == nil)
        #expect(PlayerChapter.current(in: [], at: .seconds(2)) == nil)
    }

    /// No mark at the start (or the very end); crowded ones thin out; one
    /// chapter alone marks nothing.
    @Test func marksSkipTheEndsAndThinOut() {
        func chapters(_ starts: [Double]) -> [PlayerChapter] {
            starts.enumerated().map { PlayerChapter(index: $0, start: .seconds($1), name: "C\($0)") }
        }
        #expect(PlayerChapter.marks(chapters([0, 30, 60, 90]), duration: .seconds(120)) == [0.25, 0.5, 0.75])
        #expect(PlayerChapter.marks(chapters([0, 1, 2]), duration: .seconds(100)) == [])               // all at the start
        #expect(PlayerChapter.marks(chapters([0, 50, 51, 52, 60, 99.5]), duration: .seconds(100)) == [0.5, 0.6])
        #expect(PlayerChapter.marks(chapters([0, 50]), duration: .zero) == [])
        #expect(PlayerChapter.marks(chapters([50]), duration: .seconds(100)) == [])
        // A chapter every 5 s of a 22-minute episode: at most one mark per 2.5 %.
        let dense = PlayerChapter.marks(chapters(stride(from: 0, to: 1320, by: 5).map(Double.init)), duration: .seconds(1320))
        #expect(dense.count <= 40 && dense.count >= 30)
    }
}

/// A slow start: nothing in the first second; then where it's going.
@Test func slowStartWordsAfterASecond() {
    #expect(SlowStart.delay == .seconds(1))
    #expect(SlowStart.message(resumingAt: .seconds(2530), after: .milliseconds(900)) == nil)
    #expect(SlowStart.message(resumingAt: .seconds(2530), after: .seconds(1)) == "Getting to 42:10…")
    #expect(SlowStart.message(resumingAt: .seconds(4000), after: .seconds(3)) == "Getting to 1:06:40…")
    #expect(SlowStart.message(resumingAt: nil, after: .seconds(1)) == "Getting ready…")
    #expect(SlowStart.message(resumingAt: .zero, after: .seconds(1)) == "Getting ready…")
}
