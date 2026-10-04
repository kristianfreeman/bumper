#if os(tvOS)
import AppCore
import CoreGraphics
import JellyfinAPI

/// Scrubbing thumbnails from Jellyfin's trickplay tile sheets (10.9+).
/// Each sheet is a W×H grid of thumbnails; we fetch sheets through the image
/// pipeline (cached, deduplicated) and crop the cell for a given time.
struct TrickplayProvider: Sendable {
    let info: TrickplayInfo
    let width: Int
    let client: JellyfinClient
    let itemId: String
    let mediaSourceId: String

    init?(item: BaseItem, mediaSourceId: String, client: JellyfinClient) {
        guard let byWidth = item.trickplay?[mediaSourceId] ?? item.trickplay?.values.first,
              let best = byWidth.compactMap({ (Int($0.key), $0.value) as? (Int, TrickplayInfo) }).min(by: { abs($0.0 - 320) < abs($1.0 - 320) }) else { return nil }
        self.width = best.0
        self.info = best.1
        self.client = client
        self.itemId = item.id
        self.mediaSourceId = mediaSourceId
    }

    private func location(for time: Duration) -> (sheet: Int, cell: Int)? {
        guard info.interval > 0 else { return nil }
        let index = min(info.thumbnailCount - 1, max(0, Int(time.components.seconds * 1000 / Int64(info.interval))))
        return (index / info.thumbnailsPerTile, index % info.thumbnailsPerTile)
    }

    private func request(sheet: Int) -> ImageRequest {
        ImageRequest(url: client.trickplayTileURL(itemId: itemId, mediaSourceId: mediaSourceId, width: width, index: sheet), maxPixelSize: info.width * info.tileWidth)
    }

    func thumbnail(at time: Duration) async -> CGImage? {
        guard let (sheet, cell) = location(for: time),
              let tile = try? await ImagePipeline.shared.image(for: request(sheet: sheet)) else { return nil }
        let col = cell % info.tileWidth, row = cell / info.tileWidth
        let scale = CGFloat(tile.width) / CGFloat(info.width * info.tileWidth)
        let rect = CGRect(x: CGFloat(col * info.width) * scale, y: CGFloat(row * info.height) * scale, width: CGFloat(info.width) * scale, height: CGFloat(info.height) * scale)
        return tile.cropping(to: rect)
    }

    /// Prefetch the sheets around the playhead before the user starts scrubbing.
    func warm(around time: Duration) {
        guard let (sheet, _) = location(for: time) else { return }
        ImagePipeline.shared.prefetch([max(0, sheet - 1), sheet, sheet + 1].map(request(sheet:)))
    }
}
#endif
