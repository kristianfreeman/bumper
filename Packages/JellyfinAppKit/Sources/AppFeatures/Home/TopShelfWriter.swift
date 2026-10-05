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
        var shelf = wanted.compactMap { id, title -> TopShelfSnapshot.Section? in
            guard let section = sections.first(where: { $0.id == id }), !section.items.isEmpty else { return nil }
            return .init(title: title, items: section.items.prefix(16).map { item($0, client: client) })
        }
        // Recently Added: every library's newest, newest first.
        let latest = sections.filter { $0.id.hasPrefix("latest-") }.flatMap(\.items)
            .sorted { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
        if !latest.isEmpty { shelf.append(.init(title: "Recently Added", items: latest.prefix(16).map { item($0, client: client) })) }
        let result = TopShelfSnapshot(sections: shelf).write()
        if result == .written { TVTopShelfContentProvider.topShelfContentDidChange() }
        TraceFile.write("topshelf", "\(result): " + shelf.map { "\($0.title) (\($0.items.count))" }.joined(separator: ", ") + " of sections " + sections.map(\.id).joined(separator: ","))
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
