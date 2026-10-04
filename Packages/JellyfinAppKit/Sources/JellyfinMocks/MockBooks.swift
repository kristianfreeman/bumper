public import Foundation
public import JellyfinAPI
import Synchronization

/// Audiobooks for the mock server, from TestMedia/books
/// (`scripts/make-audiobook-media.sh`): an "Audiobooks" library with a
/// one-file book with chapters and a book in three files.
///
/// Streams mimic Jellyfin's `/Audio/{id}/stream.mp3?startTimeTicks=`: the
/// files are constant-bitrate MP3, so a start time is a byte offset.
public enum MockBooks {
    struct Book: Codable {
        struct Part: Codable { var file: String; var duration: Double }
        struct Chapter: Codable { var name: String; var start: Double }
        var id: String
        var title: String
        var author: String
        var narrator: String?
        var parts: [Part]
        var chapters: [Chapter]
    }

    public static let viewId = "view-books"
    /// The test files' bitrate (64 kb/s): seconds → bytes.
    static let bytesPerSecond = 8_000.0
    private static let state = Mutex<(local: URL?, remote: URL?, books: [Book])>((nil, nil, []))

    public static func configure(directory: URL) {
        guard let data = try? Data(contentsOf: directory.appending(path: "manifest.json")),
              let books = try? JSONDecoder().decode([Book].self, from: data) else { return }
        state.withLock { $0 = (directory, nil, books) }
    }

    /// Books served by another machine (`mock-media-server` on the Mac).
    public static func configure(remote base: URL) throws {
        let books = try JSONDecoder().decode([Book].self, from: Data(contentsOf: base.appending(path: "manifest.json")))
        state.withLock { $0 = (nil, base, books) }
    }

    public static var isConfigured: Bool { state.withLock { !$0.books.isEmpty } }

    static var view: BaseItem {
        var v = BaseItem(id: viewId, name: "Audiobooks", kind: .collectionFolder)
        v.collectionType = "books"
        v.imageTags = ["Primary": "vb"]
        return v
    }

    private static var books: [Book] { state.withLock { $0.books } }

    /// Every AudioBook file (what a recursive library query returns).
    static var files: [BaseItem] { books.flatMap { book in book.parts.indices.map { part(book, $0) } } }

    /// Folders of multi-file books.
    static var folders: [BaseItem] {
        books.filter { $0.parts.count > 1 }.map { book in
            var f = BaseItem(id: book.id, name: book.title, kind: .folder)
            f.isFolder = true
            f.childCount = book.parts.count
            f.parentId = viewId
            f.imageTags = ["Primary": "b\(book.id)"]
            return f
        }
    }

    static func item(id: String) -> BaseItem? {
        if let folder = folders.first(where: { $0.id == id }) { return folder }
        return files.first { $0.id == id }
    }

    static func children(of parentId: String) -> [BaseItem]? {
        if parentId == viewId { return files }
        guard books.contains(where: { $0.id == parentId }) else { return nil }
        return files.filter { $0.parentId == parentId }
    }

    private static func part(_ book: Book, _ index: Int) -> BaseItem {
        let single = book.parts.count == 1
        let p = book.parts[index]
        var item = BaseItem(id: single ? book.id : "\(book.id)-p\(index + 1)", name: single ? book.title : "Part \(index + 1)", kind: .audioBook)
        item.album = book.title
        item.albumArtist = book.author
        item.artists = [book.author]
        item.mediaType = "Audio"
        item.runTimeTicks = Int64(p.duration * Double(BaseItem.ticksPerSecond))
        item.indexNumber = index + 1
        item.parentId = single ? viewId : book.id
        item.overview = "A short mystery, read by \(book.narrator ?? "a narrator"). Synthesized speech with long pauses, for testing Smart Speed."
        item.imageTags = ["Primary": "b\(book.id)"]
        item.productionYear = 2026
        item.userData = UserItemData()
        if single {
            item.chapters = book.chapters.map { Chapter(startPositionTicks: Int64($0.start * Double(BaseItem.ticksPerSecond)), name: $0.name) }
        }
        return item
    }

    /// `/Audio/{id}/stream.mp3?startTimeTicks=…`
    static func stream(itemId: String, startTicks: Int64) -> (Int, Data, [String: String])? {
        let (local, remote, books) = state.withLock { $0 }
        guard let (book, index) = books.lazy.compactMap({ b -> (Book, Int)? in
            if b.parts.count == 1, b.id == itemId { return (b, 0) }
            if let n = b.parts.indices.first(where: { "\(b.id)-p\($0 + 1)" == itemId }) { return (b, n) }
            return nil
        }).first else { return nil }
        let file = book.parts[index].file
        let offset = Int(Double(startTicks) / Double(BaseItem.ticksPerSecond) * bytesPerSecond)
        if let remote {
            return (302, Data(), ["Location": remote.appending(path: file).absoluteString + "?offset=\(offset)"])
        }
        guard let local, let data = try? Data(contentsOf: local.appending(path: file), options: .alwaysMapped) else { return nil }
        let body = data.count > offset ? data.subdata(in: offset..<data.count) : Data()
        return (200, body, ["Content-Type": "audio/mpeg", "Content-Length": String(body.count)])
    }
}
