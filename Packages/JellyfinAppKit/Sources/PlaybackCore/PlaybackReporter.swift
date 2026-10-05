public import AppCore
public import JellyfinAPI
import Foundation
import Instrumentation
import os

/// Reports playback state to Jellyfin (resume points, "now playing" in the
/// dashboard, play counts). Fire-and-forget: reporting must never block or
/// fail playback.
public actor PlaybackReporter {
    private let client: JellyfinClient
    private let plan: PlaybackPlan
    /// Where progress the server didn't get goes (offline), for later.
    private let outbox: PlaystateOutbox?
    private var lastReported: ContinuousClock.Instant?
    private var started = false
    private static let log = Perf.logger("reporter")

    public init(client: JellyfinClient, plan: PlaybackPlan, outbox: PlaystateOutbox? = nil) {
        self.client = client
        self.plan = plan
        self.outbox = outbox
    }

    /// Kept for later when the server can't be told now. Near the end counts
    /// as watched (as the server judges it).
    private func undelivered(_ position: Duration) {
        let duration = plan.item.runTimeTicks.map { Double($0) / Double(BaseItem.ticksPerSecond) } ?? 0
        let played = duration > 0 && position.seconds / duration >= 0.9
        outbox?.keep(itemId: plan.item.id, positionTicks: position.ticks, played: played)
    }

    private func report(position: Duration, paused: Bool, audio: Int?, subtitle: Int?) -> PlaybackProgressReport {
        PlaybackProgressReport(
            itemId: plan.item.id,
            mediaSourceId: plan.mediaSource.id,
            playSessionId: plan.playSessionId,
            positionTicks: position.ticks,
            isPaused: paused,
            playMethod: plan.method.rawValue,
            audioStreamIndex: audio ?? plan.audioStreamIndex,
            subtitleStreamIndex: subtitle ?? plan.subtitleStreamIndex
        )
    }

    public func start(position: Duration) async {
        started = true
        lastReported = .now
        do { try await client.reportPlaybackStart(report(position: position, paused: false, audio: nil, subtitle: nil)) }
        catch { Self.log.error("start report failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// Call freely (every tick is fine): throttled to one request / 10 s
    /// unless `force` (pause, seek, track change).
    public func progress(position: Duration, paused: Bool, audio: Int? = nil, subtitle: Int? = nil, force: Bool = false) async {
        guard started else { return }
        if !force, let last = lastReported, last.duration(to: .now) < .seconds(10) { return }
        lastReported = .now
        do { try await client.reportPlaybackProgress(report(position: position, paused: paused, audio: audio, subtitle: subtitle)) }
        catch { undelivered(position) }
    }

    public func stop(position: Duration) async {
        guard started else { return }
        started = false
        do { try await client.reportPlaybackStopped(report(position: position, paused: true, audio: nil, subtitle: nil)) }
        catch { undelivered(position) }
    }
}
