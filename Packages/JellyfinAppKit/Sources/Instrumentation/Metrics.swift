import Foundation
import Synchronization

/// Identifies a measured quantity. Values are recorded in milliseconds unless
/// the key says otherwise (`.count`-style keys record raw numbers).
public struct MetricKey: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, Comparable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    // Launch / navigation
    public static let launchToFirstContent: MetricKey = "launch.firstContent"
    public static let launchPreMain: MetricKey = "launch.preMain"
    public static let homeLoad: MetricKey = "home.load"
    public static let detailLoad: MetricKey = "detail.load"

    // Network
    public static let apiRequest: MetricKey = "api.request"
    public static let apiDecode: MetricKey = "api.decode"

    // Images
    public static let imageFetch: MetricKey = "image.fetch"
    public static let imageDecode: MetricKey = "image.decode"
    public static let imageMemoryHit: MetricKey = "image.memoryHit"
    public static let blurHashDecode: MetricKey = "image.blurhash"

    // UI smoothness
    /// Cumulative ms of hitch per second of interaction (Apple's hitch ratio).
    public static let hitchRatio: MetricKey = "ui.hitchRatio"
    /// Per-second-window hitch ratio, for spotting *where* hitches happen.
    public static let hitchWindow: MetricKey = "ui.hitchWindow"
    public static let frameTime: MetricKey = "ui.frameTime"

    // Playback
    public static let playbackInfo: MetricKey = "playback.info"
    public static let timeToFirstFrame: MetricKey = "playback.ttff"
    public static let seekLatency: MetricKey = "playback.seek"
    public static let rebuffer: MetricKey = "playback.rebuffer"
    public static let droppedFrames: MetricKey = "engine.droppedFrames"
}

public struct MetricSummary: Sendable, Codable, Equatable {
    public var count: Int
    public var last: Double
    public var min: Double
    public var max: Double
    public var mean: Double
    public var p50: Double
    public var p95: Double

    public init(count: Int, last: Double, min: Double, max: Double, mean: Double, p50: Double, p95: Double) {
        self.count = count; self.last = last; self.min = min; self.max = max; self.mean = mean; self.p50 = p50; self.p95 = p95
    }
}

/// Lock-protected reservoir of recent samples per metric. Cheap enough to call
/// from render loops: recording is an append into a fixed-size ring.
public final class Metrics: Sendable {
    public static let shared = Metrics()

    static let capacity = 512

    struct Ring {
        var samples: [Double] = []
        var next = 0
        var total = 0

        mutating func append(_ v: Double) {
            if samples.count < Metrics.capacity {
                samples.append(v)
            } else {
                samples[next] = v
            }
            next = (next + 1) % Metrics.capacity
            total += 1
        }
    }

    private let storage = Mutex<[MetricKey: Ring]>([:])

    public init() {}

    public func record(_ key: MetricKey, _ duration: Duration) {
        record(key, value: duration.milliseconds)
    }

    public func record(_ key: MetricKey, value: Double) {
        storage.withLock { $0[key, default: Ring()].append(value) }
    }

    public func reset() {
        storage.withLock { $0.removeAll() }
    }

    public func summary(_ key: MetricKey) -> MetricSummary? {
        storage.withLock { $0[key] }.flatMap(Self.summarize)
    }

    public func snapshot() -> [MetricKey: MetricSummary] {
        let rings = storage.withLock { $0 }
        return rings.compactMapValues(Self.summarize)
    }

    /// JSON blob keyed by metric name, used by UI tests and `perf.json` dumps.
    public func snapshotJSON() -> String {
        let dict = Dictionary(uniqueKeysWithValues: snapshot().map { ($0.key.rawValue, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(dict)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func summarize(_ ring: Ring) -> MetricSummary? {
        guard !ring.samples.isEmpty else { return nil }
        let sorted = ring.samples.sorted()
        let lastIndex = (ring.next - 1 + ring.samples.count) % ring.samples.count
        func pct(_ p: Double) -> Double {
            let idx = Int((Double(sorted.count - 1) * p).rounded())
            return sorted[idx]
        }
        return MetricSummary(
            count: ring.total,
            last: ring.samples[lastIndex],
            min: sorted.first!,
            max: sorted.last!,
            mean: sorted.reduce(0, +) / Double(sorted.count),
            p50: pct(0.5),
            p95: pct(0.95)
        )
    }
}

extension Duration {
    public var milliseconds: Double {
        let (s, atto) = components
        return Double(s) * 1_000 + Double(atto) / 1e15
    }

    public var seconds: Double { milliseconds / 1_000 }
}
