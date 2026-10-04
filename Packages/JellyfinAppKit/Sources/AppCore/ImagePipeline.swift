public import CoreGraphics
public import Foundation
import CryptoKit
import ImageIO
import Instrumentation
import Synchronization

public struct ImageRequest: Hashable, Sendable {
    public let url: URL
    /// Longest edge in *pixels* we will display at. The decoded bitmap is never
    /// larger than this, so memory ≈ what's on screen.
    public let maxPixelSize: Int
    /// Cache key, computed once (cards look it up on every render; parsing the
    /// URL each time was measurable on A10X Apple TVs). Ignores auth params so
    /// a token refresh doesn't bust the cache.
    public let key: String

    public init(url: URL, maxPixelSize: Int) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        let s = url.absoluteString
        if s.contains("api_key") || s.contains("ApiKey"), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.queryItems = c.queryItems?.filter { $0.name != "api_key" && $0.name != "ApiKey" }
            key = (c.url?.absoluteString ?? s) + "#\(maxPixelSize)"
        } else {
            key = s + "#\(maxPixelSize)"
        }
    }

    public static func == (a: Self, b: Self) -> Bool { a.key == b.key }
    public func hash(into h: inout Hasher) { h.combine(key) }
}

public enum ImagePriority: Sendable {
    case visible, prefetch

    var taskPriority: TaskPriority { self == .visible ? .userInitiated : .utility }
}

/// Fetch → disk cache → downsample/decode (off main) → memory cache.
///
/// Design goals, in order:
/// 1. A card that scrolls back into view shows its image *synchronously*
///    (`cachedImage`), never flashing a placeholder.
/// 2. Identical concurrent requests share one download + one decode.
/// 3. Decode never happens on the main thread, and is always downsampled.
public final class ImagePipeline: Sendable {
    public static let shared = ImagePipeline()

    private let memory: MemoryCache
    private let disk: DiskCache
    private let inflight = Mutex<[String: Task<CGImage, any Error>]>([:])
    private let session = Mutex<URLSession>(ImagePipeline.makeSession(protocolClasses: []))

    public init(memoryLimitBytes: Int = 192 * 1024 * 1024, diskLimitBytes: Int = 768 * 1024 * 1024) {
        memory = MemoryCache(costLimit: memoryLimitBytes)
        disk = DiskCache(name: "images", limitBytes: diskLimitBytes)
    }

    /// Mock-server injection for UI tests.
    public func configure(protocolClasses: [AnyClass]) {
        session.withLock { $0 = Self.makeSession(protocolClasses: protocolClasses) }
    }

    private static func makeSession(protocolClasses: [AnyClass]) -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = nil               // we run our own disk cache
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 20
        if !protocolClasses.isEmpty { config.protocolClasses = protocolClasses + (config.protocolClasses ?? []) }
        return URLSession(configuration: config)
    }

    // MARK: Public API

    /// Synchronous memory-cache lookup. Safe (and cheap) to call from `body`.
    public func cachedImage(for request: ImageRequest) -> CGImage? {
        let image = memory.get(request.key)
        if image != nil { Metrics.shared.record(.imageMemoryHit, value: 1) }
        return image
    }

    public func image(for request: ImageRequest, priority: ImagePriority = .visible) async throws -> CGImage {
        if let hit = memory.get(request.key) { return hit }
        let task = inflight.withLock { tasks -> Task<CGImage, any Error> in
            if let existing = tasks[request.key] { return existing }
            let task = Task(priority: priority.taskPriority) { [self] in
                defer { _ = inflight.withLock { $0.removeValue(forKey: request.key) } }
                return try await load(request)
            }
            tasks[request.key] = task
            return task
        }
        return try await task.value
    }

    /// Warms caches for items about to scroll into view.
    public func prefetch(_ requests: [ImageRequest]) {
        for request in requests where memory.get(request.key) == nil {
            Task(priority: .utility) { _ = try? await image(for: request, priority: .prefetch) }
        }
    }

    public func removeAll() async {
        memory.removeAll()
        await disk.removeAll()
    }

    // MARK: Pipeline

    private func load(_ request: ImageRequest) async throws -> CGImage {
        let data: Data
        if let cached = await disk.data(for: request.url.absoluteString) {
            data = cached
        } else {
            let urlSession = session.withLock { $0 }
            data = try await Perf.measure("image.fetch", .imageFetch) {
                let (data, response) = try await urlSession.data(from: request.url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            await disk.store(data, for: request.url.absoluteString)
        }
        let image = try Self.decode(data, maxPixelSize: request.maxPixelSize)
        memory.set(image, for: request.key)
        return image
    }

    /// ImageIO thumbnailing: decodes straight to the target size (never
    /// materialises the full-resolution bitmap) and forces the decode now, on
    /// this background thread, instead of lazily at first draw on main.
    static func decode(_ data: Data, maxPixelSize: Int) throws -> CGImage {
        try Perf.measureSync("image.decode", .imageDecode) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { throw URLError(.cannotDecodeContentData) }
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { throw URLError(.cannotDecodeContentData) }
            return image
        }
    }
}

// MARK: - Memory cache

/// Byte-cost-bounded LRU. Unlike NSCache it never evicts on a whim, so an
/// image that was on screen a moment ago is reliably still there.
final class MemoryCache: Sendable {
    private struct Entry { let image: CGImage; let cost: Int; var tick: UInt64 }
    private struct State { var entries: [String: Entry] = [:]; var cost = 0; var tick: UInt64 = 0 }

    private let state = Mutex(State())
    private let costLimit: Int

    init(costLimit: Int) { self.costLimit = costLimit }

    func get(_ key: String) -> CGImage? {
        state.withLock { s in
            guard var e = s.entries[key] else { return nil }
            s.tick &+= 1
            e.tick = s.tick
            s.entries[key] = e
            return e.image
        }
    }

    func set(_ image: CGImage, for key: String) {
        let cost = image.bytesPerRow * image.height
        state.withLock { s in
            s.tick &+= 1
            if let old = s.entries.updateValue(Entry(image: image, cost: cost, tick: s.tick), forKey: key) { s.cost -= old.cost }
            s.cost += cost
            guard s.cost > costLimit else { return }
            // Evict down to 80% in one pass so eviction cost is amortised.
            for (k, e) in s.entries.sorted(by: { $0.value.tick < $1.value.tick }) where s.cost > costLimit * 4 / 5 {
                s.entries.removeValue(forKey: k)
                s.cost -= e.cost
            }
        }
    }

    func removeAll() { state.withLock { $0 = State() } }
}

// MARK: - Disk cache

/// Content-addressed file cache in Caches/. tvOS may purge it at any time;
/// that's fine, it's only a cache.
actor DiskCache {
    private let directory: URL
    private let limitBytes: Int
    private var writesSinceTrim = 0

    init(name: String, limitBytes: Int) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: name, directoryHint: .isDirectory)
        self.limitBytes = limitBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func path(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
        return directory.appending(path: digest)
    }

    func data(for key: String) -> Data? {
        try? Data(contentsOf: path(for: key), options: .mappedIfSafe)
    }

    func store(_ data: Data, for key: String) {
        try? data.write(to: path(for: key), options: .atomic)
        writesSinceTrim += 1
        if writesSinceTrim > 200 {
            writesSinceTrim = 0
            trim()
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// LRU-ish: evict oldest-modified files until under the limit.
    private func trim() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        var entries = files.compactMap { url -> (URL, Date, Int)? in
            guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, v.contentModificationDate ?? .distantPast, v.totalFileAllocatedSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.2 }
        guard total > limitBytes else { return }
        entries.sort { $0.1 < $1.1 }
        for (url, _, size) in entries where total > limitBytes * 3 / 4 {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
