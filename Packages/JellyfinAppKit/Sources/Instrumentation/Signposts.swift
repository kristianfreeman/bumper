import Foundation
public import os

/// Central place for signposts + logging. Every hot path in the app is wrapped
/// in an interval so Instruments (Points of Interest / os_signpost) shows a
/// complete timeline: network → JSON decode → image decode → first frame.
///
/// Intervals are *also* recorded into `Metrics.shared`, so the in-app HUD and
/// UI tests can read p50/p95 without attaching Instruments.
public enum Perf {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "jellyfinapp"

    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// Measures an async operation: emits a signpost interval and records the
    /// duration (ms) under `metric`.
    @inlinable
    public static func measure<T>(
        _ name: StaticString,
        _ metric: MetricKey,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        let start = ContinuousClock.now
        defer {
            signposter.endInterval(name, state)
            Metrics.shared.record(metric, start.duration(to: .now))
        }
        return try await body()
    }

    /// Synchronous variant for CPU-bound work (decoding, layout math).
    @inlinable
    public static func measureSync<T>(
        _ name: StaticString,
        _ metric: MetricKey,
        _ body: () throws -> T
    ) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        let start = ContinuousClock.now
        defer {
            signposter.endInterval(name, state)
            Metrics.shared.record(metric, start.duration(to: .now))
        }
        return try body()
    }

    /// Point-in-time marker (e.g. "first frame rendered").
    public static func event(_ name: StaticString, _ message: String = "") {
        signposter.emitEvent(name, "\(message, privacy: .public)")
    }
}

/// A started-but-not-finished measurement, for spans that cross callbacks
/// (e.g. "tap Play" → "first video frame on screen").
public struct Span: Sendable {
    public let metric: MetricKey
    public let start: ContinuousClock.Instant

    public init(_ metric: MetricKey) {
        self.metric = metric
        self.start = .now
        Perf.event("span.begin", metric.rawValue)
    }

    @discardableResult
    public func end() -> Duration {
        let elapsed = start.duration(to: .now)
        Metrics.shared.record(metric, elapsed)
        Perf.event("span.end", metric.rawValue)
        return elapsed
    }
}
