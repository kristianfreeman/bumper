public import AppCore
public import JellyfinAPI
public import SwiftUI
import Instrumentation
import Synchronization

extension EnvironmentValues {
    /// The signed-in user's API client; image views build URLs from it.
    @Entry public var jellyfin: JellyfinClient?
    /// Blur stills / hide descriptions of unwatched episodes.
    @Entry public var hideSpoilers = false
}

extension BaseItem {
    /// Overview, unless it would spoil an unwatched episode.
    public func overview(hidingSpoilers: Bool) -> String? {
        hidingSpoilers && isSpoilerSensitive ? nil : overview
    }
}

/// Which artwork to show for an item, with Jellyfin's fallbacks applied
/// (episode → series art, missing thumb → backdrop, …).
nonisolated public enum ArtworkKind: Sendable, Hashable {
    case poster      // 2:3
    case landscape   // 16:9, prefers Thumb (has title baked in) then Backdrop
    case backdrop    // 16:9, clean art
    case logo
    case still       // episode screenshot

    public var aspectRatio: CGFloat {
        switch self {
        case .poster: 2.0 / 3.0
        case .logo: 3.0
        default: 16.0 / 9.0
        }
    }
}

nonisolated public struct ArtworkSource: Sendable, Hashable {
    public let itemId: String
    public let type: ImageType
    public let tag: String?
    public let blurHash: String?

    public static func resolve(_ item: BaseItem, _ kind: ArtworkKind) -> ArtworkSource? {
        func own(_ type: ImageType) -> ArtworkSource? {
            if type == .backdrop, let tag = item.backdropImageTags?.first {
                return ArtworkSource(itemId: item.id, type: .backdrop, tag: tag, blurHash: item.blurHash(for: .backdrop, tag: tag))
            }
            guard let tag = item.imageTags?[type.rawValue] else { return nil }
            return ArtworkSource(itemId: item.id, type: type, tag: tag, blurHash: item.blurHash(for: type, tag: tag))
        }
        let parentBackdrop: ArtworkSource? = item.parentBackdropItemId.flatMap { id in
            item.parentBackdropImageTags?.first.map { ArtworkSource(itemId: id, type: .backdrop, tag: $0, blurHash: item.blurHash(for: .backdrop, tag: $0)) }
        }
        let parentThumb: ArtworkSource? = item.parentThumbItemId.flatMap { id in
            item.parentThumbImageTag.map { ArtworkSource(itemId: id, type: .thumb, tag: $0, blurHash: item.blurHash(for: .thumb, tag: $0)) }
        }
        switch kind {
        case .poster:
            if item.kind == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag {
                return ArtworkSource(itemId: seriesId, type: .primary, tag: tag, blurHash: item.blurHash(for: .primary, tag: tag))
            }
            return own(.primary)
        case .landscape:
            if item.kind == .episode { return own(.primary) ?? parentThumb ?? parentBackdrop }
            return own(.thumb) ?? own(.backdrop) ?? parentThumb ?? parentBackdrop ?? own(.primary)
        case .backdrop:
            return own(.backdrop) ?? parentBackdrop ?? own(.thumb)
        case .logo:
            if let tag = item.imageTags?[ImageType.logo.rawValue] { return ArtworkSource(itemId: item.id, type: .logo, tag: tag, blurHash: nil) }
            return item.parentLogoItemId.flatMap { id in item.parentLogoImageTag.map { ArtworkSource(itemId: id, type: .logo, tag: $0, blurHash: nil) } }
        case .still:
            return own(.primary) ?? own(.thumb) ?? parentBackdrop
        }
    }

    /// The show's own 16:9 art for an episode (no spoilers in it).
    public static func seriesLandscape(_ item: BaseItem) -> ArtworkSource? {
        if let id = item.parentThumbItemId, let tag = item.parentThumbImageTag {
            return ArtworkSource(itemId: id, type: .thumb, tag: tag, blurHash: item.blurHash(for: .thumb, tag: tag))
        }
        if let id = item.parentBackdropItemId, let tag = item.parentBackdropImageTags?.first {
            return ArtworkSource(itemId: id, type: .backdrop, tag: tag, blurHash: item.blurHash(for: .backdrop, tag: tag))
        }
        return nil
    }

    public func request(client: JellyfinClient, pixelWidth: Int) -> ImageRequest {
        // Bucket sizes so nearby widths share one server-side resize + cache entry.
        let bucket = max(64, Int((Double(pixelWidth) / 64).rounded(.up)) * 64)
        return RequestCache.shared.request(for: self, bucket: bucket, client: client)
    }
}

/// Memoised image requests. Building a Jellyfin image URL (URLComponents +
/// percent-encoding) on every card render was a measurable share of frame
/// time on the 2017 Apple TV; the inputs rarely change, so build once.
nonisolated final class RequestCache: Sendable {
    static let shared = RequestCache()
    private struct Key: Hashable { let source: ArtworkSource; let bucket: Int; let base: URL }
    private let storage = Mutex<[Key: ImageRequest]>([:])

    func request(for source: ArtworkSource, bucket: Int, client: JellyfinClient) -> ImageRequest {
        let key = Key(source: source, bucket: bucket, base: client.baseURL)
        if let hit = storage.withLock({ $0[key] }) { return hit }
        let url = client.imageURL(itemId: source.itemId, type: source.type, tag: source.tag, options: ImageOptions(maxWidth: bucket, quality: 88))
        let request = ImageRequest(url: url, maxPixelSize: bucket)
        storage.withLock { cache in
            if cache.count > 4_000 { cache.removeAll(keepingCapacity: true) }
            cache[key] = request
        }
        return request
    }
}

/// Decoded-blurhash cache. Decoding is ~0.2 ms, but a new row reveals ~20
/// cards at once, so decoding happens in the background (`prewarm`) when
/// content arrives; `body` only ever does a lookup.
nonisolated public final class BlurHashCache: Sendable {
    public static let shared = BlurHashCache()
    private let storage = Mutex<[String: CGImage]>([:])

    func cached(_ hash: String) -> CGImage? {
        storage.withLock { $0[hash] }
    }

    func decode(_ hash: String) -> CGImage? {
        if let hit = cached(hash) { return hit }
        guard let image = BlurHash.image(hash, width: 24, height: 24) else { return nil }
        storage.withLock { cache in
            if cache.count > 1_000 { cache.removeAll(keepingCapacity: true) }
            cache[hash] = image
        }
        return image
    }

    /// Decode placeholders for a batch of items off the main thread.
    public nonisolated func prewarm(_ items: [BaseItem]) {
        let hashes = items.flatMap { item in
            [ArtworkKind.poster, .landscape, .backdrop].compactMap { ArtworkSource.resolve(item, $0)?.blurHash }
        }
        Task.detached(priority: .utility) { [self] in
            for hash in Set(hashes) { _ = decode(hash) }
        }
    }
}

/// The one image view every card uses. Shows, in order of availability:
/// memory-cached image (synchronously, no flash) → blurhash → themed surface,
/// then cross-fades to the real image when it arrives.
public struct Artwork: View {
    let kind: ArtworkKind
    let width: CGFloat
    let contentMode: ContentMode
    /// The episode's own still, which can spoil it if unwatched.
    let spoiler: Bool
    /// Shown instead of a spoiler still (Home cards: the show's art).
    /// nil → the still's blurhash.
    let spoilerAlternative: ArtworkSource?

    @Environment(\.jellyfin) private var client
    @Environment(\.hideSpoilers) private var hideSpoilers
    @Environment(\.displayScale) private var scale
    @Environment(\.theme) private var theme
    /// Keyed by request: a reused view (the hero logo as focus moves) must
    /// never show the previous item's image or skip loading the new one.
    @State private var loaded: (key: String, source: ArtworkSource, image: CGImage)?

    public init(_ source: ArtworkSource?, kind: ArtworkKind, width: CGFloat, contentMode: ContentMode = .fill, spoiler: Bool = false, spoilerAlternative: ArtworkSource? = nil) {
        self.storedSource = source
        self.kind = kind
        self.width = width
        self.contentMode = contentMode
        self.spoiler = spoiler
        self.spoilerAlternative = spoilerAlternative
    }

    /// `.landscape` (Home's Continue Watching / Next Up) swaps an unwatched
    /// episode's still for the show's art; `.still` (a series page's episode
    /// row) blurs it, since one show image on every episode says nothing.
    public init(item: BaseItem, kind: ArtworkKind, width: CGFloat, contentMode: ContentMode = .fill) {
        let source = ArtworkSource.resolve(item, kind)
        let spoiler = item.isSpoilerSensitive && source?.itemId == item.id && source?.type != .logo
        let alternative = spoiler && kind == .landscape ? ArtworkSource.seriesLandscape(item) : nil
        self.init(source, kind: kind, width: width, contentMode: contentMode, spoiler: spoiler, spoilerAlternative: alternative)
    }

    /// Spoiler-protected with no alternative: the blurhash *is* the blurred
    /// still — no extra image load, and no per-card .blur (an offscreen pass
    /// per card).
    private var hidden: Bool { spoiler && hideSpoilers && spoilerAlternative == nil }

    private let storedSource: ArtworkSource?
    private var source: ArtworkSource? { spoiler && hideSpoilers ? (spoilerAlternative ?? storedSource) : storedSource }

    private var request: ImageRequest? {
        guard !hidden, let source, let client else { return nil }
        return source.request(client: client, pixelWidth: Int(width * scale))
    }

    public var body: some View {
        let request = request
        let fresh = loaded.flatMap { $0.key == request?.key ? $0.image : nil }
        // The same artwork at its last size while a resize's loads (a window
        // being resized otherwise flashes every card back to its placeholder).
        let stale = loaded.flatMap { $0.source == source ? $0.image : nil }
        let image = fresh ?? request.flatMap { ImagePipeline.shared.cachedImage(for: $0) } ?? stale
        ZStack {
            if kind != .logo {
                if let hash = source?.blurHash, let blur = hidden ? BlurHashCache.shared.decode(hash) : BlurHashCache.shared.cached(hash) {
                    Image(decorative: blur, scale: 1).resizable()
                } else {
                    theme.surface
                }
            }
            if let image {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .task(id: request) {
            guard let request, let source, fresh == nil, ImagePipeline.shared.cachedImage(for: request) == nil else { return }
            if let fetched = try? await ImagePipeline.shared.image(for: request) {
                // Ease in rather than pop.
                withAnimation(.easeOut(duration: 0.2)) { loaded = (request.key, source, fetched) }
            }
        }
    }
}
