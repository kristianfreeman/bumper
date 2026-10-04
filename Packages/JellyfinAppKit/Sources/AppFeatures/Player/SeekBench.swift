#if os(tvOS)
import AppCore
import Foundation
import Instrumentation
import PlaybackCore
import os

/// `-seekBench`: drives the player through the moves people actually make —
/// ±10 s skips, jumps across the timeline, a burst of rapid presses — via the
/// same controller calls the remote uses, and measures each:
///
/// - `frame`:  request → first frame at the new position queued/ready
/// - `resume`: request → playback running again at the new position
/// - `dropped`: frames dropped in the second after (a catch-up stutter)
///
/// Results go to Library/Caches/perf/seekbench.json for scripts/seek-bench.sh.
@MainActor
enum SeekBench {
    struct Sample: Codable { var label: String; var frameMs: Double?; var resumeMs: Double?; var dropped: Int }

    static func run(_ controller: PlayerController) async {
        let log = Perf.logger("seekbench")
        guard let engine = controller.engine else { return }
        // Wait for steady playback.
        for _ in 0..<100 where engine.status != .playing { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .seconds(1))
        let duration = engine.duration ?? .seconds(120)
        var samples: [Sample] = []

        func measure(_ label: String, target: @escaping () -> Duration, _ action: @escaping () async -> Void) async {
            let t0 = ContinuousClock.now
            let dropped0 = engine.stats.droppedFrames
            let want = target()
            let work = Task { await action() }
            var frame: Duration?
            var resume: Duration?
            var lastInRange: Duration?
            let deadline = t0 + .seconds(8)          // VLCKit far jumps in MKV can take seconds
            while ContinuousClock.now < deadline, resume == nil || frame == nil {
                if frame == nil, let at = engine.lastSeekFrameAt, at > t0 { frame = t0.duration(to: at) }
                let now = engine.playheadNow
                if resume == nil, now >= want - .milliseconds(600), now <= want + .seconds(2) {
                    if let prev = lastInRange, now > prev + .milliseconds(30), engine.status == .playing { resume = t0.duration(to: .now) }
                    if lastInRange == nil { lastInRange = now }
                } else if resume == nil {
                    lastInRange = nil
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            await work.value
            try? await Task.sleep(for: .seconds(1))           // let any catch-up show in the drop count
            let s = Sample(label: label, frameMs: frame?.milliseconds, resumeMs: resume?.milliseconds, dropped: engine.stats.droppedFrames - dropped0)
            log.info("\(label, privacy: .public): frame \(s.frameMs.map { String(Int($0)) } ?? "–", privacy: .public) ms · resume \(s.resumeMs.map { String(Int($0)) } ?? "–", privacy: .public) ms · dropped \(s.dropped, privacy: .public)")
            TraceFile.write("seekbench", "\(label): frame \(s.frameMs.map { String(Int($0)) } ?? "–") ms · resume \(s.resumeMs.map { String(Int($0)) } ?? "–") ms · dropped \(s.dropped)")
            samples.append(s)
        }

        for delta in [10, 10, 10, -10, -10, -10] {
            let base = controller.displayTime
            await measure(delta > 0 ? "skip.fwd" : "skip.back", target: { base + .seconds(delta) }) {
                await controller.skip(by: .seconds(delta))
            }
        }
        for fraction in [0.25, 0.8, 0.1, 0.6] {
            let target = duration * fraction
            await measure("jump", target: { target }) { await controller.seek(to: target) }
        }
        // Five presses 60 ms apart: should land once, at +50 s (from 10 %,
        // so +50 s stays inside the clip).
        await controller.seek(to: duration * 0.1)
        try? await Task.sleep(for: .seconds(1))
        let base = controller.displayTime
        await measure("burst", target: { base + .seconds(50) }) {
            for i in 0..<5 {
                Task { await controller.skip(by: .seconds(10)) }
                if i < 4 { try? await Task.sleep(for: .milliseconds(60)) }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        write(samples, engine: engine, tag: controller.benchTag)
    }

    private static func write(_ samples: [Sample], engine: any PlayerEngine, tag: String?) {
        func summary(_ values: [Double]) -> MetricSummary? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))] }
            return MetricSummary(count: sorted.count, last: values.last!, min: sorted.first!, max: sorted.last!, mean: sorted.reduce(0, +) / Double(sorted.count), p50: pct(0.5), p95: pct(0.95))
        }
        var metrics: [String: MetricSummary] = [:]
        for kind in ["skip", "jump", "burst"] {
            let group = samples.filter { $0.label.hasPrefix(kind) }
            metrics["seek.\(kind).frame"] = summary(group.compactMap(\.frameMs))
            metrics["seek.\(kind).resume"] = summary(group.compactMap(\.resumeMs))
            metrics["seek.\(kind).dropped"] = summary(group.map { Double($0.dropped) })
            let missing = group.filter { $0.resumeMs == nil }.count
            if missing > 0 { metrics["seek.\(kind).failed"] = summary([Double(missing)]) }
        }
        struct Output: Codable { var engine: String; var video: String; var metrics: [String: MetricSummary]; var samples: [Sample] }
        let out = Output(engine: engine.kind.rawValue, video: engine.stats.video, metrics: metrics, samples: samples)
        let url = PerfRecorder.shared.latestURL.deletingLastPathComponent().appending(path: tag.map { "seekbench-\($0).json" } ?? "seekbench.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(out).write(to: url, options: .atomic)
        Perf.logger("seekbench").info("SEEKBENCH written")
    }
}
#endif
