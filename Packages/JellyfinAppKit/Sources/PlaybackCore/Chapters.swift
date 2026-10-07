import Foundation
public import JellyfinAPI

/// A chapter as the player shows it: where it starts, what it's called, and
/// which of the server's chapter images is its own.
public struct PlayerChapter: Sendable, Hashable, Identifiable {
    /// Its place in the item's chapters, as the server lists them: the
    /// index of its image (`/Items/{id}/Images/Chapter/{index}`).
    public let index: Int
    public let start: Duration
    public let name: String
    public let imageTag: String?
    public var id: Int { index }

    public init(index: Int, start: Duration, name: String, imageTag: String? = nil) {
        self.index = index
        self.start = start
        self.name = name
        self.imageTag = imageTag
    }
}

extension PlayerChapter {
    /// The item's chapters in order, each with a name. Ones past the end
    /// (another cut's) and repeats of the same start are left out.
    public static func list(_ chapters: [Chapter], runtime: Duration?) -> [PlayerChapter] {
        let sorted = chapters.enumerated().sorted { $0.element.startPositionTicks < $1.element.startPositionTicks }
        var out: [PlayerChapter] = []
        for (index, chapter) in sorted {
            let start = Duration.ticks(max(0, chapter.startPositionTicks))
            if let runtime, runtime > .zero, start >= runtime { continue }
            if out.last?.start == start { continue }
            out.append(PlayerChapter(index: index, start: start, name: name(chapter.name, number: out.count + 1), imageTag: chapter.imageTag))
        }
        return out
    }

    /// Its own name, or "Chapter 3" for one without a real one: empty, a
    /// ripper's "Chapter 03", or a bare timestamp ("00:12:30.000").
    public static func name(_ raw: String?, number: Int) -> String {
        let name = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let unnamed = name.isEmpty
            || name.wholeMatch(of: /(?i)chapter\s*\d*/) != nil
            || name.wholeMatch(of: /[\d:.,]+/) != nil
        return unnamed ? "Chapter \(number)" : name
    }

    /// The chapter playing at `time`: the last to have started. A little
    /// leeway, so a seek to a chapter that lands just short still counts.
    public static func current(in chapters: [PlayerChapter], at time: Duration) -> PlayerChapter? {
        chapters.last { $0.start <= time + .milliseconds(500) }
    }

    /// Where the timeline marks chapters, as fractions of its length: none
    /// at the very ends, and none closer than `minimumGap` to the last one
    /// — a mark every few pixels says nothing (DVD rips with a chapter
    /// every few seconds), so they thin out.
    public static func marks(_ chapters: [PlayerChapter], duration: Duration, minimumGap: Double = 0.025) -> [Double] {
        guard duration > .zero, chapters.count > 1 else { return [] }
        var out: [Double] = []
        var last = 0.0
        for chapter in chapters {
            let at = chapter.start / duration
            guard at >= minimumGap, at <= 1 - minimumGap, at - last >= minimumGap else { continue }
            out.append(at)
            last = at
        }
        return out
    }
}
