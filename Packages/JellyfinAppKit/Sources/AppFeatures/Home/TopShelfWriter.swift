#if os(tvOS)
import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import TopShelf
import TVServices

/// Keeps the Top Shelf (above Bumper's icon on the Home Screen) in step with
/// Home: what's in progress and what's next, each a tap from playing.
@MainActor
enum TopShelfWriter {
    static func update(_ sections: [BrowseSection], client: JellyfinClient) {
        // Mock runs (tests, device benchmarks) leave the real shelf alone.
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("-mock") || args.contains("-writeTopShelf") else { return }
        let wanted = [("resume", "Continue Watching"), ("nextup", "Next Up")]
        let shelf = wanted.compactMap { id, title -> TopShelfSnapshot.Section? in
            guard let section = sections.first(where: { $0.id == id }), !section.items.isEmpty else { return nil }
            return .init(title: title, items: section.items.prefix(12).map { item($0, client: client) })
        }
        if TopShelfSnapshot(sections: shelf).write() {
            TVTopShelfContentProvider.topShelfContentDidChange()
            TraceFile.write("topshelf", "updated: " + shelf.map { "\($0.title) (\($0.items.count))" }.joined(separator: ", "))
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
        let image = (ArtworkSource.resolve(item, .landscape) ?? ArtworkSource.resolve(item, .poster))?.request(client: client, pixelWidth: 1000).url
        return .init(id: item.id, title: item.seriesName ?? item.name ?? "", subtitle: subtitle, imageURL: image, progress: item.progress)
    }
}
#endif
