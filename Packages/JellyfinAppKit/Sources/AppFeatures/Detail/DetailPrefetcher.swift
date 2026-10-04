#if os(tvOS)
import AppCore
import DesignSystem
import Foundation
import Instrumentation
import JellyfinAPI

/// Fetches a title's full details (and big artwork) while its card is merely
/// *focused*, so opening it is instant. Results also go to the persistent
/// ContentCache, so re-visits paint immediately even across launches
/// (stale-while-revalidate; the detail page still refreshes in background).
@MainActor
final class DetailPrefetcher {
    static let shared = DetailPrefetcher()

    private var inflight: [String: Task<Void, Never>] = [:]
    private var ready: [String: (item: BaseItem, at: ContinuousClock.Instant)] = [:]
    private static let freshness: Duration = .seconds(90)

    static func cacheKey(_ id: String) -> String { "detail-\(id)" }

    /// Full item if we fetched it recently.
    func freshItem(_ id: String) -> BaseItem? {
        guard let entry = ready[id], entry.at.duration(to: .now) < Self.freshness else { return nil }
        return entry.item
    }

    func prefetch(_ item: BaseItem, client: JellyfinClient, displayScale: CGFloat = 2) {
        let id = item.id
        guard freshItem(id) == nil, inflight[id] == nil else { return }
        // Backdrop + logo at detail-page size, straight into the image caches.
        let requests = [(ArtworkKind.backdrop, 1920.0), (.logo, 640.0)].compactMap { kind, width in
            ArtworkSource.resolve(item, kind)?.request(client: client, pixelWidth: Int(width * displayScale))
        }
        ImagePipeline.shared.prefetch(requests)
        inflight[id] = Task { [weak self] in
            defer { self?.inflight[id] = nil }
            guard let full = try? await client.item(id: id) else { return }
            self?.store(full)
        }
    }

    func store(_ item: BaseItem) {
        ready[item.id] = (item, .now)
        if ready.count > 200 { ready = ready.filter { $0.value.at.duration(to: .now) < Self.freshness } }
        Task { await ContentCache.shared.store(item, for: Self.cacheKey(item.id)) }
    }
}
#endif
