import TopShelf
import TVServices

/// Bumper's Top Shelf: Continue Watching and Next Up, from the snapshot the
/// app writes when Home loads. Select (and Play) start it straight away:
/// Bumper opens into the player, resuming.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        completionHandler(Self.content())
    }

    static func content() -> (any TVTopShelfContent)? {
        guard let snapshot = TopShelfSnapshot.read() else { return nil }
        let sections = snapshot.sections.compactMap { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? in
            let items = section.items.prefix(12).map { item in
                let shelf = TVTopShelfSectionedItem(identifier: item.id)
                shelf.title = item.subtitle.map { "\(item.title) · \($0)" } ?? item.title
                shelf.imageShape = item.shape == .wide ? .square : .poster   // libraries a little wider than the posters (.hdtv was ~3× their size)
                if let url = item.imageURL { shelf.setImageURL(url, for: [.screenScale1x, .screenScale2x]) }
                if let progress = item.progress { shelf.playbackProgress = progress }
                shelf.playAction = TVTopShelfAction(url: item.playURL)
                shelf.displayAction = TVTopShelfAction(url: item.playURL)
                return shelf
            }
            guard !items.isEmpty else { return nil }
            let collection = TVTopShelfItemCollection(items: Array(items))
            collection.title = section.title
            return collection
        }
        return sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections)
    }
}
