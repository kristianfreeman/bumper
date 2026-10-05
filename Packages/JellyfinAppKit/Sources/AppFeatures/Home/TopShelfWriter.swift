#if os(tvOS)
import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import TopShelf
import TVServices

/// Keeps the Top Shelf (above Bumper's icon on the Home Screen) in step with
/// Home: a few things to pick up, a few new ones, and your libraries.
@MainActor
enum TopShelfWriter {
    /// A little of each, not everything: what to pick up, what's new, and
    /// ways into the app.
    static let rowLength = 6

    static func update(_ sections: [BrowseSection], client: JellyfinClient, usage: [String: Double] = [:]) {
        // Mock runs (tests, device benchmarks) leave the real shelf alone.
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("-mock") || args.contains("-writeTopShelf") else { return }
        Task {
            var views = LibraryOrder.ordered((try? await client.userViews().items) ?? [], scores: usage)
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
        // Browse: a tile per library, most used first.
        let browse = Self.links(for: views, sections: sections, client: client)
        if !browse.isEmpty { shelf.append(.init(title: "Browse", items: browse)) }

        let result = TopShelfSnapshot(sections: shelf).write()
        if result == .written { TVTopShelfContentProvider.topShelfContentDidChange() }
        TraceFile.write("topshelf", "\(result): " + shelf.map { "\($0.title) (\($0.items.count))" }.joined(separator: ", "))
    }

    // MARK: Browse

    /// Libraries worth a tile: what you browse, not playlists or folders.
    static let browsable: Set<String> = ["movies", "tvshows", "boxsets", "books", "music", "homevideos", "musicvideos"]

    /// A tile per library, most used first, with its own artwork from the
    /// server (Jellyfin's library image), or else its newest item's: real
    /// pictures, like Apple's own shelves; nothing drawn by us.
    static func links(for views: [BaseItem], sections: [BrowseSection], client: JellyfinClient) -> [TopShelfSnapshot.Item] {
        views.filter { browsable.contains($0.collectionType ?? "") }.compactMap { view in
            let newest = sections.first { $0.id.hasSuffix("-\(view.id)") }?.items.first
            let art = ArtworkSource.resolve(view, .landscape) ?? ArtworkSource.resolve(view, .poster)
                ?? newest.flatMap { ArtworkSource.resolve($0, .landscape) }
            guard let url = art?.request(client: client, pixelWidth: 800).url else { return nil }
            return .init(id: "link-\(view.id)", title: view.name ?? "Library", imageURL: url,
                         link: TopShelfSnapshot.Link.library(view.id).url, shape: .wide)
        }
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
