#if os(tvOS)
import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import SwiftUI
import TopShelf
import TVServices
import UIKit

/// Keeps the Top Shelf (above Bumper's icon on the Home Screen) in step with
/// Home: a few things to pick up, a few new ones, and tiles into the app.
@MainActor
enum TopShelfWriter {
    /// A little of each, not everything: what to pick up, what's new, and
    /// ways into the app.
    static let rowLength = 6

    static func update(_ sections: [BrowseSection], client: JellyfinClient) {
        // Mock runs (tests, device benchmarks) leave the real shelf alone.
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("-mock") || args.contains("-writeTopShelf") else { return }
        Task {
            var views = (try? await client.userViews().items) ?? []
            // A books library gets a tile only when it holds audiobooks (as in the sidebar).
            for view in views where view.collectionType == "books" {
                var q = ItemQuery(parentId: view.id, includeItemTypes: [.audioBook], limit: 1)
                q.fields = []
                let page = try? await client.items(q)
                if (page?.totalRecordCount ?? 0) == 0 && (page?.items.isEmpty ?? true) { views.removeAll { $0.id == view.id } }
            }
            write(sections, views: views, client: client)
        }
    }

    private static func write(_ sections: [BrowseSection], views: [BaseItem], client: JellyfinClient) {
        var shelf: [TopShelfSnapshot.Section] = []
        // Continue Watching: what's in progress, then the next episodes.
        let resume = sections.first { $0.id == "resume" }?.items ?? []
        let nextUp = sections.first { $0.id == "nextup" }?.items ?? []
        var seen = Set<String>()
        let pickUp = (resume + nextUp).filter { seen.insert($0.seriesId ?? $0.id).inserted }.prefix(rowLength)
        if !pickUp.isEmpty { shelf.append(.init(title: "Continue Watching", items: pickUp.map { item($0, client: client) })) }
        // Recently Added: every library's newest, newest first.
        let latest = sections.filter { $0.id.hasPrefix("latest-") }.flatMap(\.items)
            .sorted { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
        if !latest.isEmpty { shelf.append(.init(title: "Recently Added", items: latest.prefix(rowLength).map { item($0, client: client) })) }
        // Browse: a tile for each library, then Tonight and Search.
        let browse = Self.links(for: views)
        if !browse.isEmpty { shelf.append(.init(title: "Browse", items: browse)) }

        let result = TopShelfSnapshot(sections: shelf).write()
        if result == .written { TVTopShelfContentProvider.topShelfContentDidChange() }
        TraceFile.write("topshelf", "\(result): " + shelf.map { "\($0.title) (\($0.items.count))" }.joined(separator: ", "))
    }

    // MARK: Link tiles

    struct Tile {
        let kind: String
        let title: String
        let symbol: String
        /// The file's name: the kind, or the library's id for a generic tile.
        var key: String? = nil
    }

    static func tile(for library: BaseItem) -> Tile? {
        switch library.collectionType {
        case "movies": Tile(kind: "movies", title: "Movies", symbol: "film")
        case "tvshows": Tile(kind: "tvshows", title: "TV Shows", symbol: "tv")
        case "boxsets": Tile(kind: "collections", title: "Collections", symbol: "square.stack")
        case "books": Tile(kind: "audiobooks", title: "Audiobooks", symbol: "headphones")
        case "music": Tile(kind: "music", title: "Music", symbol: "music.note")
        case "homevideos": Tile(kind: "videos", title: "Videos", symbol: "video")
        case "playlists": nil                                    // not a place to browse to
        default: Tile(kind: "library", title: library.name ?? "Library", symbol: "square.grid.2x2", key: "library-\(library.id)")
        }
    }

    static func links(for views: [BaseItem]) -> [TopShelfSnapshot.Item] {
        var items: [TopShelfSnapshot.Item] = []
        for view in views {
            guard let tile = tile(for: view) else { continue }
            items.append(.init(id: "link-\(view.id)", title: view.name ?? tile.title, imageURL: art(tile),
                               link: TopShelfSnapshot.Link.library(view.id).url))
        }
        items.append(.init(id: "link-tonight", title: "Tonight", imageURL: art(Tile(kind: "tonight", title: "Tonight", symbol: "moon.stars")),
                           link: TopShelfSnapshot.Link.tonight.url))
        items.append(.init(id: "link-search", title: "Search", imageURL: art(Tile(kind: "search", title: "Search", symbol: "magnifyingglass")),
                           link: TopShelfSnapshot.Link.search.url))
        return items
    }

    /// The tile's artwork as a file the system can load: the brand kit's
    /// (`ShelfTile-<kind>` in the asset catalog) or the stand-in, drawn once
    /// per build into the shared container.
    static func art(_ tile: Tile) -> URL? {
        guard let dir = TopShelfSnapshot.directory?.appending(path: "Tiles", directoryHint: .isDirectory) else { return nil }
        let url = dir.appending(path: "\(tile.key ?? tile.kind)-\(Brand.build).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let png: Data?
        if let kit = UIImage(named: "ShelfTile-\(tile.kind)") {
            png = kit.pngData()
        } else {
            let renderer = ImageRenderer(content: ShelfTileArt(title: tile.title, symbol: tile.symbol))
            renderer.scale = 2
            png = renderer.uiImage?.pngData()
        }
        guard let png else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try? png.write(to: url, options: .atomic)) != nil ? url : nil
    }

    private static func item(_ item: BaseItem, client: JellyfinClient) -> TopShelfSnapshot.Item {
        var subtitle: String?
        if item.seriesName != nil {
            let number = item.parentIndexNumber.flatMap { s in item.indexNumber.map { "S\(s) E\($0)" } }
            subtitle = [number, item.name].compactMap { $0 }.joined(separator: " · ")
        } else if let year = item.productionYear {
            subtitle = String(year)
        }
        // Posters (tall, so about seven fit across): an episode shows its series'.
        let image = (ArtworkSource.resolve(item, .poster) ?? ArtworkSource.resolve(item, .landscape))?.request(client: client, pixelWidth: 500).url
        return .init(id: item.id, title: item.seriesName ?? item.name ?? "", subtitle: subtitle, imageURL: image, progress: item.progress)
    }
}
#endif
