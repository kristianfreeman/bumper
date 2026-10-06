import AppCore
import Companion
import CoreGraphics
import Foundation
import Instrumentation
import JellyfinAPI
import MediaPlayer
import Observation
import PlaybackCore
import VLCPlayback
import os

/// Orchestrates one playback session: plan → display mode → engine →
/// reporting, plus everything around the picture (segments, subtitles,
/// trickplay, up-next).
@MainActor
@Observable
final class PlayerController {
    enum Phase: Equatable { case preparing, playing, failed(String), finished }

    private(set) var phase: Phase = .preparing
    private(set) var engine: (any PlayerEngine)?
    var plan: PlaybackPlan?
    private(set) var segments: [MediaSegment] = []
    private(set) var activeSegment: MediaSegment?
    private(set) var nextEpisode: BaseItem?
    var subtitleTrack: SubtitleTrack?
    var selectedSubtitle: Int?
    /// "Find Subtitles": the search and its results, and the found subtitle in use.
    var subtitleSearch: SubtitleSearchState = .idle
    var foundSubtitle: FoundSubtitle?
    private(set) var trickplay: TrickplayProvider?
    var subtitleText: String?

    @ObservationIgnored private let request: PlaybackRequest
    @ObservationIgnored let app: AppModel
    @ObservationIgnored private var reporter: PlaybackReporter?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var skippedSegments: Set<String> = []
    @ObservationIgnored private var sleepFading = false
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private let totalSpan = Span("playback.tapToFrame")
    private static let log = Perf.logger("player")

    init(request: PlaybackRequest, app: AppModel) {
        self.request = request
        self.app = app
        isBackground = request.background
        transport.target = self
        transport.log = { TraceFile.write("input", $0) }
        phonePlayPause = NotificationCenter.default.addObserver(forName: .companionPlayPause, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.transport.togglePlayPause(source: "iPhone") }
        }
    }

    var item: BaseItem { details ?? plan?.item ?? request.item }
    /// Background: plays on and on (round to the first episode again) and
    /// tells the server nothing. Starts from the request; switched with
    /// `setBackground(_:)` while playing.
    private(set) var isBackground: Bool
    /// The show's first episode, where Background goes after the last.
    @ObservationIgnored private var firstEpisode: BaseItem?
    @ObservationIgnored private var client: JellyfinClient?
    /// The full item (year, rating, trickplay…): shelves and episode lists
    /// hand the player a lightweight one.
    private(set) var details: BaseItem?
    var benchTag: String? { app.options.benchTag }
    var subtitleOptions: [MediaStream] { plan?.mediaSource.subtitleStreams ?? [] }
    var audioOptions: [MediaTrack] { engine?.audioTracks ?? [] }

    // MARK: Lifecycle

    func start() async {
        guard let session = app.session else { return }
        ThemeMusic.shared.stop(fadeOut: .milliseconds(300))
        let client = session.client
        // Request the TV mode switch immediately from what we already know.
        if !app.settings.matchContent { TraceFile.write("display", "matching is off in the app's settings") }
        if app.settings.matchContent {
            DisplayModeManager.request(for: request.item.mediaStreams?.first { $0.type == .video } ?? request.item.mediaSources?.first?.videoStream)
        }
        do {
            let matching = app.settings.matchContent
            let plan: PlaybackPlan
            let engine: any PlayerEngine
            if let ready = await app.takePrepared(for: request) {
                // Opened and buffered while Play had focus: nothing left but to start.
                plan = ready.plan
                engine = ready.engine
                self.plan = plan
                self.engine = engine
                TraceFile.write("player", "Plan: \(plan.engine.rawValue) \(plan.method.rawValue) — prepared")
                // The plan knows the stream (a shelf's item often has no frame
                // rate): ask with it, and wait for the TV's switch before the
                // picture moves — starting in ~80 ms, the switch came after.
                if matching {
                    DisplayModeManager.request(for: plan.mediaSource.videoStream)
                    await DisplayModeManager.waitForSwitch()
                }
            } else {
                let start = request.resume ? request.item.resumePosition : nil
                if let file = app.downloads?.localFile(for: request.item.id), let record = app.downloads?.record(request.item.id),
                   let source = record.item.mediaSources?.first(where: { $0.id == (request.mediaSourceId ?? record.mediaSourceId) }) ?? record.item.mediaSources?.first {
                    // Downloaded: the same player, from the file on this device.
                    plan = app.planner.localPlan(item: request.item, source: source, file: file, startPosition: start,
                                                 audioIndex: request.audioIndex, subtitleIndex: request.subtitleIndex == -1 ? nil : request.subtitleIndex)
                } else if let prewarmed = app.takePrewarmedPlan(for: request) {
                    plan = try await prewarmed.value
                } else {
                    plan = try await app.planner.plan(
                        item: request.item, client: client, startPosition: start,
                        mediaSourceId: request.mediaSourceId, audioIndex: request.audioIndex,
                        subtitleIndex: request.subtitleIndex == -1 ? nil : request.subtitleIndex
                    )
                }
                self.plan = plan
                Self.log.info("Plan: \(plan.engine.rawValue, privacy: .public) \(plan.method.rawValue, privacy: .public) — \(plan.reasons.joined(separator: "; "), privacy: .public)")
                TraceFile.write("player", "Plan: \(plan.engine.rawValue) \(plan.method.rawValue) — \(plan.reasons.joined(separator: "; ")) — \(plan.url.path())")
                if matching { DisplayModeManager.request(for: plan.mediaSource.videoStream) }
                engine = app.makeEngine(plan.engine)
                self.engine = engine
                // The TV's HDMI resync (1–3 s on real TVs) runs *concurrently* with
                // open + buffer + first-frame decode; the clock only starts once
                // both are done. Cost = max(switch, load), not the sum.
                async let modeSwitch: Void = matching ? DisplayModeManager.waitForSwitch() : ()
                try await engine.load(plan, autoplay: false)
                await modeSwitch
            }
            engine.play()
            phase = .playing
            let ready = totalSpan.end()
            Self.log.info("Tap → playing in \(ready.milliseconds, privacy: .public) ms (mode switch overlapped)")
            TraceFile.write("player", "Tap → playing in \(Int(ready.milliseconds)) ms")
            // What the viewer sees: the press until the picture is actually
            // moving (play() returns before AVPlayer has a frame).
            let tapSpan = totalSpan
            Task { [weak self] in
                guard let self, let engine = self.engine else { return }
                // Moving = the backend's clock rising (its starting value can be
                // a stream offset, e.g. MPEG-TS PTS; VLCKit reports every 100 ms).
                var last = engine.playheadNow
                for _ in 0..<500 {
                    try? await Task.sleep(for: .milliseconds(10))
                    let now = engine.playheadNow
                    defer { last = now }
                    if now > last {
                        let ms = tapSpan.start.duration(to: .now).milliseconds
                        Metrics.shared.record("playback.tapToMoving", value: ms)
                        TraceFile.write("player", "Tap → moving in \(Int(ms)) ms")
                        return
                    }
                }
            }

            // Background tells the server nothing: no reporter at all.
            self.client = client
            if !isBackground {
                let reporter = PlaybackReporter(client: client, plan: plan, outbox: app.outbox)
                self.reporter = reporter
                Task { await reporter.start(position: plan.startPosition) }
            }
            updateNowPlaying()
            configureRemoteCommands()

            trickplay = TrickplayProvider(item: plan.item, mediaSourceId: plan.mediaSource.id, client: client)
            trickplay?.warm(around: plan.startPosition)
            Task { await loadDetails(client: client, plan: plan) }
            Task { await loadSidecars(client: client, plan: plan) }
            await applyInitialSubtitles(plan: plan, client: client)
            runLoop()
            if app.options.seekBench { Task { await SeekBench.run(self) } }
        } catch {
            phase = .failed(error.localizedDescription)
            Self.log.error("Playback failed: \(error.localizedDescription, privacy: .public)")
            TraceFile.write("player", "Playback failed: \(error.localizedDescription)")
        }
    }

    /// Turns Background on or off mid-play. On: what's been watched so far is
    /// reported once (a resume point), then nothing more. Off: reporting
    /// starts again from here, as if this were a normal play.
    func setBackground(_ on: Bool) {
        guard on != isBackground, let engine, let plan else { return }
        isBackground = on
        let position = engine.currentTime
        TraceFile.write("player", "background \(on ? "on" : "off") at \(Int(position.seconds))s")
        if on {
            if let reporter { Task { await reporter.stop(position: position) } }
            reporter = nil
        } else if let client {
            let reporter = PlaybackReporter(client: client, plan: plan, outbox: app.outbox)
            self.reporter = reporter
            Task { await reporter.start(position: position) }
        }
    }

    func stop() async {
        app.nowPlaying = nil
        // Runs from end-of-item *and* from the view disappearing: once only.
        guard phase != .finished else { return }
        phase = .finished
        loop?.cancel()
        let position = engine?.currentTime ?? .zero
        engine?.stop()
        if let reporter { await reporter.stop(position: position) }
        DisplayModeManager.reset()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        removeRemoteCommands()
        PerfRecorder.shared.writeIfChanged()          // TTFF/seek/decode numbers for this play
    }

    /// 4 Hz housekeeping: subtitles, segments, reporting, end-of-item.
    private func runLoop() {
        loop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let engine = self.engine else { return }
                let now = engine.currentTime
                self.subtitleText = self.subtitleTrack?.text(at: now)
                self.updateSegment(now)
                if tick % 4 == 0, let reporter = self.reporter {
                    let paused = engine.status == .paused
                    Task { await reporter.progress(position: now, paused: paused) }
                }
                if tick % 2 == 0 {                                   // for the companion app
                    self.app.nowPlaying = NowPlayingInfo(item: self.item, position: now.seconds,
                                                         duration: (engine.duration ?? self.item.runtime ?? .zero).seconds, paused: engine.status == .paused)
                }
                if engine.status == .ended { await self.finishedItem(); return }
                if engine.kind == .native, case .failed(let message) = engine.status {
                    await self.switchToVLC(reason: "AVPlayer error: \(message)")
                    continue
                }
                if await self.applySleepTimer(engine) { return }
                tick += 1
            }
        }
    }

    // MARK: Segments (skip intro / credits)

    private func updateSegment(_ now: Duration) {
        let current = segments.first { $0.range.contains(now) && [.intro, .recap, .preview, .commercial, .outro].contains($0.type) }
        if current?.id != activeSegment?.id { activeSegment = current }
        if let seg = current, seg.type == .intro || seg.type == .recap, app.settings.skipIntrosAutomatically, !skippedSegments.contains(seg.id) {
            skippedSegments.insert(seg.id)
            Task { await skip(seg) }
        }
    }

    func skip(_ segment: MediaSegment) async {
        skippedSegments.insert(segment.id)
        if segment.type == .outro, nextEpisode != nil, app.settings.autoplayNextEpisode {
            await finishedItem()
            return
        }
        await seek(to: .ticks(segment.endTicks))
    }

    private func loadSidecars(client: JellyfinClient, plan: PlaybackPlan) async {
        async let segs = Self.loadSegments(client: client, item: plan.item)
        if plan.item.kind == .episode, let seriesId = plan.item.seriesId {
            if let eps = try? await client.episodes(seriesId: seriesId, seasonId: nil).items,
               let idx = eps.firstIndex(where: { $0.id == plan.item.id }) {
                // Background goes round: after the last, the first again.
                if idx + 1 < eps.count { nextEpisode = eps[idx + 1] }
                firstEpisode = eps.first
            }
        }
        segments = await segs
    }

    /// Server segments (Jellyfin 10.10+ MediaSegments, filled by a provider
    /// plugin), else the Intro Skipper plugin's legacy endpoint, else
    /// chapter names. Logged so "Skip Intro never shows" is diagnosable.
    static func loadSegments(client: JellyfinClient, item: BaseItem) async -> [MediaSegment] {
        let id = item.id
        if let server = try? await client.mediaSegments(itemId: id), !server.isEmpty {
            log.info("Segments: \(server.count, privacy: .public) from MediaSegments")
            return server
        }
        if item.kind == .episode, let skipper = try? await client.introSkipperSegments(episodeId: id), !skipper.isEmpty {
            log.info("Segments: \(skipper.count, privacy: .public) from Intro Skipper")
            return skipper
        }
        let full = item.chapters == nil ? try? await client.item(id: id, fields: [.chapters]) : item
        let chapters = MediaSegment.fromChapters(full?.chapters ?? [], itemId: id, runtimeTicks: full?.runTimeTicks ?? item.runTimeTicks)
        log.info("Segments: \(chapters.count, privacy: .public) from chapter names (\(full?.chapters?.count ?? 0, privacy: .public) chapters)")
        return chapters
    }

    /// Fades audio over the timer's last seconds; at zero, stops and closes
    /// the player. True when it stopped playback.
    private func applySleepTimer(_ engine: any PlayerEngine) async -> Bool {
        let timer = app.sleepTimer
        if let volume = timer.fadeVolume {
            engine.setVolume(volume)
            sleepFading = true
        } else if sleepFading {
            engine.setVolume(1)                       // timer cancelled mid-fade
            sleepFading = false
        }
        guard timer.hasExpired else { return false }
        Self.log.info("Sleep timer: stopping playback")
        timer.reset()
        await stop()
        app.playback = nil
        return true
    }

    private func finishedItem() async {
        Self.log.info("Finished item at \(self.engine?.currentTime.seconds ?? -1, privacy: .public)s status \(String(describing: self.engine?.status), privacy: .public)")
        TraceFile.write("player", "Finished item at \(self.engine?.currentTime.seconds ?? -1)s")
        await stop()
        if app.sleepTimer.mode == .endOfItem {        // "End of current episode": no next one
            Self.log.info("Sleep timer: end of item")
            app.sleepTimer.reset()
            app.playback = nil
            return
        }
        // Background: on to the next (round to the first; a film again),
        // still telling the server nothing.
        if isBackground {
            app.playback = PlaybackRequest(item: nextEpisode ?? firstEpisode ?? item, resume: false, background: true)
            return
        }
        // Queue first: the next thing in the plan, in order.
        if app.queue.contains(item.id) {
            let next = app.queue.next(after: item.id)
            app.queue.finished(item.id)
            if let next {
                TraceFile.write("queue", "next in plan: \(next.name ?? next.id)")
                app.playback = PlaybackRequest(item: next, resume: true)
                return
            }
        }
        if app.settings.autoplayNextEpisode, let next = nextEpisode {
            app.playback = PlaybackRequest(item: next, resume: true)
        } else {
            app.playback = nil
        }
    }

    // MARK: Transport

    enum PlayPauseIntent: String { case toggle, play, pause }

    /// The remote's behaviour (pause, scrub, skip, scan); every input path —
    /// presses, the touch surface, Now Playing — goes through it.
    let transport = TransportModel()
    @ObservationIgnored private var phonePlayPause: (any NSObjectProtocol)?

    /// Now Playing's commands. On an Apple TV the remote's Play/Pause button
    /// arrives only as these — as "play" or "pause", picked from what the
    /// system last heard — so a "pause" while paused is the button pressed
    /// again, not a no-op: it plays (a living-room TV ignored the second press
    /// and only Select resumed). Each is one press; the transport drops the
    /// same press arriving twice.
    func playPause(_ intent: PlayPauseIntent = .toggle, via source: String) {
        if intent != .toggle, (intent == .play) == (isPlaying && !transport.isScrubbing) {
            TraceFile.write("input", "\(source) \(intent.rawValue) while already \(isPlaying ? "playing" : "paused"): taken as the button")
        }
        transport.togglePlayPause(source: source)
    }

    private func reportState() {
        guard let engine else { return }
        if let reporter { let pos = engine.currentTime; let paused = engine.status == .paused; Task { await reporter.progress(position: pos, paused: paused, force: true) } }
        updateNowPlaying()
    }

    func togglePlayPause() { playPause(.toggle, via: "ui") }

    // MARK: Seeking

    /// Where the user has asked to be: the latest seek target while one is
    /// in flight, else the engine's position. The UI shows this, so a press
    /// moves the time instantly, and skips stack (+10 +10 +10 = +30) instead
    /// of each starting from a position that hasn't moved yet.
    var displayTime: Duration { inFlightSeek ?? engine?.currentTime ?? .zero }
    private(set) var inFlightSeek: Duration?
    @ObservationIgnored private var seekGeneration = 0
    @ObservationIgnored private var pendingSeek: Duration?
    @ObservationIgnored private var serialSeek: Task<Void, Never>?

    /// Each backend says how it wants rapid seeks fed (measured on device):
    /// VLCKit gets the latest target immediately; AVPlayer gets one seek at a
    /// time, then straight to the newest target — never a backlog either way.
    func seek(to time: Duration) async {
        guard let engine else { return }
        let target = min(max(.zero, time), engine.duration ?? time)
        inFlightSeek = target
        if engine.prefersSerialSeeks {
            pendingSeek = target
            if let running = serialSeek { await running.value; return }
            let task = Task { [weak self] in
                while let self, let next = self.pendingSeek {
                    self.pendingSeek = nil
                    await engine.seek(to: next)
                }
                self?.finishSeek(at: target, engine: engine)
                self?.serialSeek = nil
            }
            serialSeek = task
            await task.value
        } else {
            seekGeneration += 1
            let generation = seekGeneration
            await engine.seek(to: target)
            if generation == seekGeneration { finishSeek(at: target, engine: engine) }
        }
    }

    private func finishSeek(at target: Duration, engine: any PlayerEngine) {
        let landed = inFlightSeek ?? target
        inFlightSeek = nil
        trickplay?.warm(around: landed)
        if let reporter { Task { await reporter.progress(position: landed, paused: engine.status == .paused, force: true) } }
        updateNowPlaying()
    }

    func skip(by delta: Duration) async {
        await seek(to: displayTime + delta)
    }

    // MARK: Tracks

    func selectAudio(_ id: Int) async {
        await engine?.selectAudio(id)
    }

    func selectSubtitle(_ index: Int?) async {
        selectedSubtitle = index
        foundSubtitle = nil
        subtitleTrack = nil
        subtitleText = nil
        guard let plan, let engine else { return }
        let stream = index.flatMap { i in plan.mediaSource.subtitleStreams.first { $0.index == i } }
        // AVPlayer takes text subtitles (as WebVTT from the server); ASS and
        // bitmaps hand this item to VLCKit, from where it is.
        if engine.kind == .native, let stream, !Codecs.avPlayerSubtitles.contains((stream.codec ?? "").lowercased()) {
            await switchToVLC(reason: "Subtitles \(stream.codec ?? "?")")
        }
        guard let engine = self.engine, let client = app.session?.client else { return }
        if engine.rendersSubtitles {
            // VLCKit draws them (ASS styling, PGS bitmaps). Sidecar files go
            // by URL in their own format.
            let external = stream.flatMap { s -> URL? in
                guard s.isExternal == true else { return nil }
                return app.downloads?.subtitleFile(itemId: plan.item.id, index: s.index, format: Self.fileExtension(for: s.codec))
                    ?? s.deliveryUrl.flatMap(client.absoluteURL(serverRelative:))
                    ?? client.subtitleURL(itemId: plan.item.id, mediaSourceId: plan.mediaSource.id, streamIndex: s.index, format: Self.fileExtension(for: s.codec))
            }
            await engine.selectSubtitle(stream, external: external)
        } else if let stream {
            // AVPlayer: WebVTT overlaid by the player (styled by the user's preset).
            // A download's saved copy first (no server offline).
            let url = app.downloads?.subtitleFile(itemId: plan.item.id, index: stream.index, format: "vtt")
                ?? stream.deliveryUrl.flatMap(client.absoluteURL(serverRelative:))
                ?? client.subtitleURL(itemId: plan.item.id, mediaSourceId: plan.mediaSource.id, streamIndex: stream.index, format: "vtt")
            if let (data, _) = try? await client.session.data(from: url) {
                subtitleTrack = SubtitleParser.parse(data, format: url.pathExtension)
            }
        }
    }

    static func fileExtension(for codec: String?) -> String { DownloadStore.subtitleExtension(codec) }

    private func applyInitialSubtitles(plan: PlaybackPlan, client: JellyfinClient) async {
        let streams = plan.mediaSource.mediaStreams ?? []
        let chosen: Int?
        if let explicit = request.subtitleIndex {
            chosen = explicit >= 0 ? explicit : nil            // -1 = user picked Off
        } else {
            switch app.settings.subtitleMode {
            case .off: chosen = nil
            case .forcedOnly: chosen = plan.mediaSource.subtitleStreams.first { $0.isForced == true }?.index
            case .always, .serverDefault:
                chosen = SubtitleSelection.choose(from: streams, serverDefault: plan.subtitleStreamIndex, preferredLanguages: Locale.preferredLanguages)
            }
        }
        if let chosen {
            let title = plan.mediaSource.subtitleStreams.first { $0.index == chosen }?.displayTitle ?? "#\(chosen)"
            Self.log.info("Subtitles on by default: \(title, privacy: .public)")
            await selectSubtitle(chosen)
        }
    }

    // MARK: Scrub previews

    @ObservationIgnored private var thumbnailCache: [Int: CGImage] = [:]

    private func loadDetails(client: JellyfinClient, plan: PlaybackPlan) async {
        guard let full = try? await client.item(id: plan.item.id) else { return }
        details = full
        if trickplay == nil {
            trickplay = TrickplayProvider(item: full, mediaSourceId: plan.mediaSource.id, client: client)
            trickplay?.warm(around: engine?.currentTime ?? plan.startPosition)
        }
        TraceFile.write("player", trickplay.map { "trickplay \($0.width) px, every \($0.info.interval) ms" } ?? "no trickplay for this item")
    }

    /// Server trickplay when the library has it, else a frame from the
    /// backend; cached per 5 s so dragging back and forth is free.
    func scrubThumbnail(at time: Duration) async -> CGImage? {
        let bucket = Int(time.seconds / 5)
        if let hit = thumbnailCache[bucket] { return hit }
        var image = await trickplay?.thumbnail(at: time)
        if image == nil, let engine {
            var at = Duration.seconds(Double(bucket) * 5 + 2.5)
            if let end = engine.duration, end > .seconds(1) { at = min(at, end - .seconds(1)) }
            image = await engine.thumbnail(at: at)
        }
        if let image {
            thumbnailCache[bucket] = image
            if thumbnailCache.count > 400 { thumbnailCache.removeAll() }
        }
        return image
    }

    /// Text cue the player overlays (AVPlayer path); VLCKit draws its own.
    var currentCue: String? { subtitleText }

    /// The picture's width ÷ height: what's decoding, else what the server says.
    var videoAspect: CGFloat? {
        if let f = engine?.videoFormat, f.width > 0, f.height > 0 { return CGFloat(f.width) / CGFloat(f.height) }
        if let v = plan?.mediaSource.videoStream, let w = v.width, let h = v.height, w > 0, h > 0 { return CGFloat(w) / CGFloat(h) }
        return nil
    }

    /// What's showing, as the backend reports it: the VLCKit track name, or
    /// "WebVTT" for the overlay. (Read by UI tests.)
    var subtitleStatus: String {
        guard let engine else { return "off" }
        if engine.rendersSubtitles { return engine.activeSubtitleTrack ?? "off" }
        return subtitleTrack == nil ? "off" : "WebVTT"
    }

    // MARK: Backends


    /// AVPlayer failed (to open or mid-playback), or the item needs
    /// something only VLCKit does: VLCKit takes over from the current
    /// position and keeps the item for the rest of its playback.
    private func switchToVLC(reason: String) async {
        guard let old = engine, old.kind == .native, var next = plan else { return }
        let position = max(old.currentTime, old.playheadNow)
        // Paused by the person, not "not moving yet": a hand-off at the very
        // start (AVPlayer not yet playing) left VLCKit paused on frame one.
        let wasPaused = old.status == .paused && phase == .playing && position > .seconds(1) && !transport.isScrubbing && !isPlaying
        Self.log.notice("AVPlayer → VLCKit at \(position.seconds, privacy: .public)s: \(reason, privacy: .public)")
        TraceFile.write("player", "AVPlayer → VLCKit at \(position.seconds)s: \(reason)")
        old.stop()
        next.engine = .vlc
        next.startPosition = position
        next.reasons.append("Switched to VLCKit: \(reason)")
        plan = next
        let engine = app.makeEngine(.vlc)
        self.engine = engine
        do {
            try await engine.load(next, autoplay: !wasPaused)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: System integration

    private func updateNowPlaying() {
        guard let engine else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.name ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.currentTime.seconds,
            MPNowPlayingInfoPropertyPlaybackRate: engine.status == .paused ? 0.0 : Double(engine.rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let d = engine.duration { info[MPMediaItemPropertyPlaybackDuration] = d.seconds }
        if let series = item.seriesName { info[MPMediaItemPropertyAlbumTitle] = series }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        remoteTargets = [
            (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.playPause(.toggle, via: "NowPlaying") }
                return .success
            }),
            // On hardware the remote's button often arrives as these instead
            // of the toggle — unhandled, the press did nothing.
            (center.playCommand, center.playCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.playPause(.play, via: "NowPlaying") }
                return .success
            }),
            (center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.playPause(.pause, via: "NowPlaying") }
                return .success
            }),
            (center.skipForwardCommand, center.skipForwardCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { Task { await self?.skip(by: .seconds(10)) } }
                return .success
            }),
            (center.skipBackwardCommand, center.skipBackwardCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { Task { await self?.skip(by: .seconds(-10)) } }
                return .success
            }),
        ]
    }

    /// Every play used to add targets and never remove them.
    private func removeRemoteCommands() {
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets = []
    }
}
extension PlayerController: TransportTarget {
    var position: Duration { displayTime }
    var length: Duration { engine?.duration ?? item.runtime ?? .zero }
    var isPlaying: Bool { engine.map { $0.status != .paused } ?? false }

    func play() {
        engine?.play()
        reportState()
    }

    func pause() {
        engine?.pause()
        reportState()
    }
}
