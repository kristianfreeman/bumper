import Foundation
import JellyfinAPI

/// A book as the listener thinks of it, built from Jellyfin's AudioBook
/// items: one file (an M4B with chapters, say), or a folder of files (part 1,
/// part 2, …) played back to back. Positions are book seconds.
nonisolated struct Audiobook: Identifiable, Hashable, Sendable {
    struct Chapter: Hashable, Sendable {
        var title: String
        var start: Double
    }

    /// The file's id (one file) or the folder's id (several).
    var id: String
    var title: String
    var author: String?
    /// The item whose Primary image is the cover.
    var cover: BaseItem
    /// In playing order.
    var parts: [BaseItem]
    var chapters: [Chapter]
    var overview: String?
    var year: Int?

    var duration: Double { parts.reduce(0) { $0 + Self.seconds($1) } }

    func partStart(_ index: Int) -> Double {
        parts.prefix(index).reduce(0) { $0 + Self.seconds($1) }
    }

    /// Which part holds book time `t`, and where in it.
    func locate(_ t: Double) -> (part: Int, offset: Double) {
        var start = 0.0
        for (i, part) in parts.enumerated() {
            let length = Self.seconds(part)
            if t < start + length || i == parts.count - 1 { return (i, max(0, min(t - start, length))) }
            start += length
        }
        return (0, 0)
    }

    func chapterIndex(at t: Double) -> Int? {
        guard !chapters.isEmpty else { return nil }
        return chapters.lastIndex { $0.start <= t + 0.25 } ?? 0
    }

    func chapterRange(_ index: Int) -> ClosedRange<Double> {
        let start = chapters[index].start
        let end = index + 1 < chapters.count ? chapters[index + 1].start : duration
        return start...max(start, end)
    }

    /// Where Resume starts: inside the first unfinished part.
    var resumePosition: Double? {
        for (i, part) in parts.enumerated() where !part.isPlayed {
            let offset = part.resumePosition.map { Double($0.ticks) / Double(BaseItem.ticksPerSecond) } ?? 0
            let t = partStart(i) + offset
            return t > 1 ? t : nil
        }
        return nil
    }

    var isFinished: Bool { parts.allSatisfy(\.isPlayed) }

    var progress: Double? {
        guard let t = resumePosition, duration > 0 else { return nil }
        return t / duration
    }

    /// The book as a card: the cover's artwork, the book's title, author and
    /// progress (a card's id is the book's).
    var card: BaseItem {
        var c = cover
        c.id = id
        c.name = title
        c.albumArtist = author
        c.runTimeTicks = Int64(duration * Double(BaseItem.ticksPerSecond))
        var data = UserItemData()
        data.playbackPositionTicks = resumePosition.map { Int64($0 * Double(BaseItem.ticksPerSecond)) }
        data.played = isFinished
        c.userData = data
        return c
    }

    static func seconds(_ item: BaseItem) -> Double {
        Double(item.runTimeTicks ?? 0) / Double(BaseItem.ticksPerSecond)
    }

    /// AudioBook files (a library, recursively) → books: files sharing a
    /// folder are one book; a file straight in the library is its own.
    static func group(_ files: [BaseItem], libraryId: String) -> [Audiobook] {
        var order: [String] = []
        var byKey: [String: [BaseItem]] = [:]
        for file in files {
            let key = file.parentId == nil || file.parentId == libraryId ? file.id : file.parentId!
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(file)
        }
        return order.map { key in book(id: key, parts: byKey[key]!) }
    }

    static func book(id: String, parts unsorted: [BaseItem]) -> Audiobook {
        let parts = unsorted.sorted { ($0.indexNumber ?? 0, $0.name ?? "") < ($1.indexNumber ?? 0, $1.name ?? "") }
        let first = parts[0]
        var chapters: [Chapter] = []
        var start = 0.0
        for part in parts {
            if let own = part.chapters, !own.isEmpty {
                chapters += own.sorted { $0.startPositionTicks < $1.startPositionTicks }.enumerated().map { i, c in
                    Chapter(title: c.name ?? "Chapter \(chapters.count + i + 1)", start: start + Double(c.startPositionTicks) / Double(BaseItem.ticksPerSecond))
                }
            } else if parts.count > 1 {
                chapters.append(Chapter(title: part.name ?? "Part \(chapters.count + 1)", start: start))
            }
            start += seconds(part)
        }
        let title = parts.count == 1 ? (first.name ?? first.album ?? "Untitled") : (first.album ?? first.name ?? "Untitled")
        return Audiobook(id: id, title: title, author: first.albumArtist ?? first.artists?.first, cover: first, parts: parts,
                         chapters: chapters, overview: first.overview, year: first.productionYear)
    }
}
