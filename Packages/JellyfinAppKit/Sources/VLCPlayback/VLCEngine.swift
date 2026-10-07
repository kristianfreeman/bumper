#if os(tvOS) || os(iOS) || os(macOS)
public import AppCore
public import JellyfinAPI
public import Observation
public import PlaybackCore
#if canImport(UIKit)
public import UIKit
#else
public import AppKit
#endif
import CoreGraphics
import Foundation
import Instrumentation
import os
@preconcurrency import VLCKit

/// The VLCKit backend: everything AVPlayer doesn't take (MKV, ASS/SSA, PGS,
/// DTS, TrueHD, MPEG-2, VC-1, AV1, …) and any item AVPlayer fails on.
/// VLCKit owns demux, decode, A/V sync, rendering and subtitles; this class
/// only adapts it to `PlayerEngine` and maps Jellyfin stream indexes to
/// VLC's tracks.
@MainActor
@Observable
public final class VLCEngine: PlayerEngine {
    public let kind: EngineKind = .vlc
    public private(set) var status: PlaybackStatus = .idle
    public private(set) var currentTime: Duration = .zero
    public private(set) var duration: Duration?
    public private(set) var rate: Float = 1
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var selectedAudioTrack: Int?
    public let rendersSubtitles = true
    public let prefersSerialSeeks = false
    public private(set) var activeSubtitleTrack: String?
    public private(set) var videoFormat: VideoFormatInfo?
    public private(set) var stats = EngineStats()
    @ObservationIgnored public private(set) var lastSeekFrameAt: ContinuousClock.Instant?

    public var playheadNow: Duration { Self.duration(player.time) ?? currentTime }
    public var videoView: PlatformView { surface }

    @ObservationIgnored private let player: VLCMediaPlayer
    @ObservationIgnored private let surface = PlatformView()
    @ObservationIgnored private let events = Events()
    @ObservationIgnored private var plan: PlaybackPlan?
    @ObservationIgnored private var firstFrameSpan: Span?
    @ObservationIgnored private var loggedBadClock = false
    @ObservationIgnored private var heldAtStart = false
    @ObservationIgnored private var started: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var seekWaiter: (target: Duration, continuation: CheckedContinuation<Void, Never>)?
    @ObservationIgnored private var hasPlayed = false
    @ObservationIgnored private var startsPaused = false
    /// Resume point the opening seek is heading for (nil once reached).
    @ObservationIgnored private var startTarget: Duration?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    /// The hardware decoder gave nothing for this item: decode it in software
    /// from here on (see `watchDecoder`).
    @ObservationIgnored private var softwareDecode = false

    private static let log = Perf.logger("vlc-engine")

    public init(subtitleStyle: VLCSubtitleStyle) {
        // Diagnostics: `-vlcPlayerOptions "opt1=x opt2"` (A/B-testing
        // player-level options — the video output — on a device; written
        // without their dashes, which the argument parser would take as flags).
        let extra = (UserDefaults.standard.string(forKey: "vlcPlayerOptions") ?? "").split(separator: " ").map { $0.hasPrefix("-") ? String($0) : "--" + $0 }
        player = VLCMediaPlayer(options: subtitleStyle.options + extra)
        if !extra.isEmpty { TraceFile.write("vlc", "player options: \(extra.joined(separator: " "))") }
        if ProcessInfo.processInfo.arguments.contains("-vlcLog") {   // VLC's own log (diagnostics)
            // `-traceStderr` too: to the console (streams back through a device
            // launch; copying files off a busy TV hangs). Else a file to pull.
            if TraceFile.enabled && !ProcessInfo.processInfo.arguments.contains("-traceStderr") {
                let url = TraceFile.directory.appending(path: "vlc.log")
                try? FileManager.default.createDirectory(at: TraceFile.directory, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                if let handle = try? FileHandle(forWritingTo: url) {
                    let logger = VLCFileLogger(fileHandle: handle)
                    logger.level = .debug
                    player.libraryInstance.loggers = [logger]
                }
            } else {
                let logger = VLCConsoleLogger()
                logger.level = .debug
                player.libraryInstance.loggers = [logger]
            }
        }
        #if canImport(UIKit)
        surface.backgroundColor = .black
        #else
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.black.cgColor
        #endif
        player.drawable = surface
        player.timeChangeUpdateInterval = 0.1     // default 1 s: the on-screen clock would lag
        events.engine = self
        player.delegate = events
        stats.engineName = "VLCKit"
    }

    // MARK: Load

    public func load(_ plan: PlaybackPlan, autoplay: Bool) async throws {
        self.plan = plan
        status = .loading
        firstFrameSpan = Span(.timeToFirstFrame)
        stats.method = plan.method.rawValue
        stats.notes = plan.reasons
        duration = plan.item.runtime
        videoFormat = Self.formatInfo(plan.mediaSource.videoStream)
        stats.video = videoFormat?.summary ?? "—"
        stats.audio = plan.selectedAudio.map { "\($0.displayTitle ?? $0.codec ?? "") · VLCKit" } ?? "—"
        audioTracks = plan.mediaSource.audioStreams.filter { $0.isExternal != true }.map { s in
            MediaTrack(id: s.index, title: s.displayTitle ?? s.language ?? s.codec ?? "Audio", language: s.language, codec: s.codec, isDefault: s.isDefault == true)
        }
        selectedAudioTrack = plan.selectedAudio?.index

        guard let media = VLCMedia(url: plan.url) else { throw VLCEngineError.cannotOpen }
        // On the chosen audio track, with no subtitle until the player
        // selects one. (No `:start-time`: VLC 4 makes it the clip's in-point,
        // so the clock, the length and every later seek become relative to
        // it. A seek right after play() starts there instead.)
        if let index = plan.audioStreamIndex, let n = audioOrder(of: index) { media.addOption(":audio-track=\(n)") }
        media.addOption(":sub-track=-1")
        media.addOption(":network-caching=500")
        // The clock runs on the system clock, not the audio output: after a
        // seek VLC otherwise waits ~1 s for the audio output to restart before
        // the picture moves (measured on an Apple TV 4K: ±10 s skip 1.9 s →
        // 0.76 s). VLC keeps sync by resampling audio slightly when needed.
        media.addOption(":clock-master=monotonic")
        // Read ahead further and treat forward seeks within it as reads, not
        // new HTTP requests: ±10 s skips 0.96 → 0.70 s on an Apple TV 4K.
        media.addOption(":prefetch-buffer-size=131072")          // KiB (128 MiB)
        media.addOption(":prefetch-seek-threshold=67108864")     // bytes (64 MiB)
        // MKV: seek with the file's Cues. VLC's default MKV demuxer treats
        // them as unconfirmed and, over HTTP (no fast seek to check them),
        // seeks from the first cluster instead — reading everything up to a
        // resume point: 15 min into a 1 GB file failed after 20 s; trusted,
        // 0.8 s (Apple TV 4K).
        if Self.isMatroska(plan.mediaSource.container) { media.addOption(":demux=mkv_trusted") }
        // AVI: FFmpeg's reader. VLC's own works out display times from the
        // decode times AVI carries, and with packed-B-frame DivX/Xvid (most
        // older AVIs) they come out a frame or two early — "picture is too
        // late", and over half the frames dropped (an SD sitcom at 15 fps on
        // an Apple TV 4K). FFmpeg's unpacks them: every frame, none late.
        if Self.isAVI(plan.mediaSource.container) { media.addOption(":demux=avformat") }
        // MPEG-4 Part 2 (DivX, Xvid, DivX 3, H.263): VLC's software decoder.
        // VLCKit hands it to VideoToolbox, which rejected real DivX/Xvid files
        // ("bad data", the session restarted over and over) and showed
        // nothing; FFmpeg decodes SD MPEG-4 with room to spare.
        // Interlaced H.264 too: VideoToolbox hands field-coded streams over a
        // field at a time, twice the frame rate, and most were dropped (a
        // 1080i25 film at 20 fps); in software, every frame.
        let video = plan.mediaSource.videoStream
        let h264 = (video?.codec ?? "").lowercased() == "h264"
        let interlacedH264 = h264 && video?.isInterlaced == true
        // 10-bit H.264: no Apple decoder has it; VLC found that out after ~8 s
        // of trying (and a restart in software from there failed to show).
        let tenBitH264 = h264 && (video?.bitDepth ?? 8) > 8
        if Self.isMPEG4Part2(video?.codec) || interlacedH264 || tenBitH264 || softwareDecode { media.addOption(":codec=avcodec") }
        // Diagnostics: `-vlcMediaOptions ":opt1 :opt2"` (A/B-testing VLC options on a device).
        for option in (UserDefaults.standard.string(forKey: "vlcMediaOptions") ?? "").split(separator: " ") {
            media.addOption(String(option))
        }
        // Prepared-but-held: VLC opens, shows the first frame and waits for
        // play(). It reports "playing" and then "paused"; loading is done at
        // the pause — a play() sent before it would be swallowed by it.
        if !autoplay { media.addOption(":start-paused") }
        startsPaused = !autoplay
        heldAtStart = !autoplay
        player.media = media

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            started = c
            player.play()
            if plan.startPosition > .zero {
                startTarget = plan.startPosition
                player.time = VLCTime(int: Int32(clamping: Int64(plan.startPosition.milliseconds)))
            }
            Task { [weak self] in                     // never hang a play request
                try? await Task.sleep(for: .seconds(20))
                self?.finishStart(throwing: VLCEngineError.timedOut)
            }
        }
        startStats()
    }

    /// Already decoded in software (the watchdog has nothing to switch to).
    nonisolated static func decodesInSoftware(_ plan: PlaybackPlan?) -> Bool {
        guard let v = plan?.mediaSource.videoStream else { return false }
        let h264 = (v.codec ?? "").lowercased() == "h264"
        return isMPEG4Part2(v.codec) || (h264 && (v.isInterlaced == true || (v.bitDepth ?? 8) > 8))
    }

    nonisolated static func isMPEG4Part2(_ codec: String?) -> Bool {
        ["mpeg4", "msmpeg4", "msmpeg4v1", "msmpeg4v2", "msmpeg4v3", "h263", "divx", "xvid", "mp4v"].contains((codec ?? "").lowercased())
    }

    nonisolated static func isAVI(_ container: String?) -> Bool {
        (container ?? "").lowercased().split(separator: ",").contains { $0 == "avi" || $0 == "divx" }
    }

    nonisolated static func isMatroska(_ container: String?) -> Bool {
        (container ?? "").lowercased().split(separator: ",").contains { $0 == "mkv" || $0 == "webm" || $0 == "matroska" }
    }

    private func finishStart(throwing error: (any Error)? = nil) {
        guard let c = started else { return }
        started = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    // MARK: Transport

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
        status = .paused
    }

    public func setRate(_ rate: Float) {
        self.rate = rate
        player.rate = rate
    }

    public func seek(to time: Duration) async {
        let span = Span(.seekLatency)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            seekWaiter?.continuation.resume()            // a newer seek supersedes
            seekWaiter = (time, c)
            player.time = VLCTime(int: Int32(clamping: Int64(time.milliseconds)))
            Task { [weak self] in                         // bounded: never wedge the UI
                try? await Task.sleep(for: .seconds(3))
                self?.finishSeek(target: time)
            }
        }
        currentTime = time
        span.end()
    }

    private func finishSeek(target: Duration) {
        guard let waiter = seekWaiter, waiter.target == target else { return }
        seekWaiter = nil
        lastSeekFrameAt = .now
        waiter.continuation.resume()
    }

    public func stop() {
        statsTask?.cancel()
        statsTask = nil
        player.delegate = nil
        player.stop()
        seekWaiter?.continuation.resume()
        seekWaiter = nil
        finishStart(throwing: CancellationError())
        status = .idle
    }

    public func setVolume(_ volume: Float) {
        player.audio?.volume = Int32(max(0, min(1, volume)) * 100)
    }

    // MARK: Tracks (Jellyfin stream index ↔ VLC track, by order within type)

    public func selectAudio(_ streamIndex: Int) async {
        guard let n = audioOrder(of: streamIndex), n < player.audioTracks.count else { return }
        player.audioTracks[n].isSelectedExclusively = true
        selectedAudioTrack = streamIndex
    }

    public func selectSubtitle(_ stream: MediaStream?, external: URL?) async {
        defer { refreshActiveSubtitle() }
        guard let stream else {
            player.deselectAllTextTracks()
            return
        }
        if let external {
            let before = player.textTracks.count
            player.addPlaybackSlave(external, type: .subtitle, enforce: true)
            // VLC adds the file's track a moment later (later still when
            // paused) and doesn't always select it: wait for it, then do.
            for _ in 0..<15 {
                try? await Task.sleep(for: .milliseconds(150))
                if player.textTracks.count > before, let added = player.textTracks.last {
                    if !added.isSelected { added.isSelectedExclusively = true }
                    break
                }
            }
            return
        }
        let embedded = (plan?.mediaSource.subtitleStreams ?? []).filter { $0.isExternal != true }
        guard let n = embedded.firstIndex(where: { $0.index == stream.index }), n < player.textTracks.count else { return }
        player.textTracks[n].isSelectedExclusively = true
    }

    /// What VLC itself says is selected (tracks can appear a moment after open).
    private func refreshActiveSubtitle() {
        activeSubtitleTrack = player.textTracks.first { $0.isSelected }?.trackName
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            self.activeSubtitleTrack = self.player.textTracks.first { $0.isSelected }?.trackName
        }
    }

    // MARK: Scrub thumbnails

    @ObservationIgnored private var thumbnailer: VLCMediaThumbnailer?
    @ObservationIgnored private var thumbnailWaiter: CheckedContinuation<CGImage?, Never>?
    @ObservationIgnored private let thumbnailEvents = ThumbnailEvents()

    /// One at a time (each opens the stream); a newer request replaces a
    /// waiting one, so dragging never builds a backlog.
    public func thumbnail(at time: Duration) async -> CGImage? {
        guard let plan, let media = VLCMedia(url: plan.url) else { return nil }
        if Self.isMatroska(plan.mediaSource.container) { media.addOption(":demux=mkv_trusted") }
        // AVI: FFmpeg's reader. VLC's own works out display times from the
        // decode times AVI carries, and with packed-B-frame DivX/Xvid (most
        // older AVIs) they come out a frame or two early — "picture is too
        // late", and over half the frames dropped (an SD sitcom at 15 fps on
        // an Apple TV 4K). FFmpeg's unpacks them: every frame, none late.
        if Self.isAVI(plan.mediaSource.container) { media.addOption(":demux=avformat") }
        // MPEG-4 Part 2 (DivX, Xvid, DivX 3, H.263): VLC's software decoder.
        // VLCKit hands it to VideoToolbox, which rejected real DivX/Xvid files
        // ("bad data", the session restarted over and over) and showed
        // nothing; FFmpeg decodes SD MPEG-4 with room to spare.
        // Interlaced H.264 too: VideoToolbox hands field-coded streams over a
        // field at a time, twice the frame rate, and most were dropped (a
        // 1080i25 film at 20 fps); in software, every frame.
        let video = plan.mediaSource.videoStream
        let h264 = (video?.codec ?? "").lowercased() == "h264"
        let interlacedH264 = h264 && video?.isInterlaced == true
        // 10-bit H.264: no Apple decoder has it; VLC found that out after ~8 s
        // of trying (and a restart in software from there failed to show).
        let tenBitH264 = h264 && (video?.bitDepth ?? 8) > 8
        if Self.isMPEG4Part2(video?.codec) || interlacedH264 || tenBitH264 || softwareDecode { media.addOption(":codec=avcodec") }   // see load()
        media.addOption(":no-audio")
        thumbnailer?.cancel()
        thumbnailWaiter?.resume(returning: nil)
        return await withCheckedContinuation { continuation in
            thumbnailWaiter = continuation
            thumbnailEvents.done = { [weak self] image in
                guard let self, let waiter = self.thumbnailWaiter else { return }
                self.thumbnailWaiter = nil
                waiter.resume(returning: image)
            }
            let t = VLCMediaThumbnailer(media: media, andDelegate: thumbnailEvents)
            t.thumbnailWidth = 480
            t.thumbnailHeight = 270
            t.snapshotTime = VLCTime(int: Int32(clamping: Int64(time.milliseconds)))
            t.preciseSeek = false
            t.hardwareDecodingEnabled = true
            thumbnailer = t
            t.fetchThumbnail()
        }
    }

    private func audioOrder(of streamIndex: Int) -> Int? {
        plan?.mediaSource.audioStreams.filter { $0.isExternal != true }.firstIndex { $0.index == streamIndex }
    }

    // MARK: Events (main queue)

    fileprivate func stateChanged(_ state: VLCMediaPlayerState) {
        TraceFile.write("vlc", "state \(state.rawValue) at \(player.time.value?.intValue ?? -1) ms")
        switch state {
        case .opening:
            if hasPlayed, status != .paused { status = .buffering }
        case .playing:
            hasPlayed = true
            guard !(startsPaused && started != nil) else { return }   // the held pause follows
            status = .playing
            finishStart()
        case .paused:
            status = .paused
            finishStart()
        case .stopped, .stopping:
            if hasPlayed { status = .ended }
        case .nothingSpecial:
            break
        case .error:
            let message = "VLCKit could not play this item"
            Self.log.error("\(message, privacy: .public)")
            status = .failed(message)
            finishStart(throwing: VLCEngineError.playbackFailed)
        @unknown default:
            break
        }
    }

    fileprivate func timeChanged() {
        guard var now = Self.duration(player.time) else { return }
        // Opened held (`:start-paused`, a prepared item) on the monotonic
        // clock, VLC's `time` after play() can be the system clock's, not the
        // file's — hours into a 20-minute clip (seen in the simulator, and
        // reported to the server as progress). Past the end it can't be
        // right: the position along the file (0…1) is.
        if let length = duration, now > length + .seconds(2) {
            now = .milliseconds(Int64(Double(player.position) * length.milliseconds))
            // After a held start (`:start-paused`) the picture can stay on its
            // first frame too (seen in the simulator): one seek to where it is
            // sets the clock to the file's again. Only then — a real Apple TV
            // didn't need it, and a seek as playback starts isn't free.
            if heldAtStart {
                heldAtStart = false
                player.time = VLCTime(int: Int32(clamping: Int64(now.milliseconds)))
                TraceFile.write("vlc", "clock wrong after a held start: re-seek to \(Int(now.milliseconds)) ms")
            }
            if !loggedBadClock {
                loggedBadClock = true
                let reported = Self.duration(player.time)?.seconds ?? -1
                Self.log.error("VLC clock \(reported, privacy: .public) s past the end (\(length.seconds, privacy: .public) s): using its position instead")
                TraceFile.write("vlc", "clock \(Int(reported)) s past the end (\(Int(length.seconds)) s): using its position")
            }
        }
        // Until the opening seek lands, the clock still shows the file's
        // start: hold the resume point (no 0:00 flash, no early "first frame").
        if let target = startTarget {
            // (A target past the end never lands: let the clock go.)
            let reachable = duration.map { target < $0 } ?? true
            guard !reachable || now >= target - .seconds(3) else { currentTime = target; return }
            startTarget = nil
        }
        currentTime = now
        // "Playing" arrives before any picture; a video output with the
        // clock moving is the first frame on screen.
        if let span = firstFrameSpan, player.hasVideoOut || plan?.mediaSource.videoStream == nil {
            firstFrameSpan = nil
            let ms = span.end().milliseconds
            Self.log.info("First frame in \(ms, privacy: .public) ms")
            TraceFile.write("vlc", "First frame in \(Int(ms)) ms at \(Int(now.milliseconds)) ms (asked \(Int(plan?.startPosition.milliseconds ?? 0)))")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                TraceFile.write("vlc", "clock 2 s later: \(self.player.time.value?.intValue ?? -1) ms, position \(self.player.position)")
                self.describeSurface()
            }
        }
        if duration == nil || duration == .zero, let length = Self.duration(player.media?.length), length > .zero { duration = length }
        // VLC reports the requested time straight away; the picture is back
        // once the clock moves on from it.
        if let waiter = seekWaiter, now > waiter.target + .milliseconds(40), now < waiter.target + .seconds(2) { finishSeek(target: waiter.target) }
    }

    private func startStats() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            var tick = 0
            var last: (decoded: Int, lost: Int, late: Int, shown: Int) = (0, 0, 0, 0)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let media = self.player.media else { return }
                let s = media.statistics
                tick += 1
                // Every few seconds in the trace (10 by default): frames decoded, shown, dropped and late
                // over that time ("laggy" on a real TV is one of these).
                if tick % TraceFile.statsWindow == 0 {
                    let now = (decoded: Int(s.decodedVideo), lost: Int(s.lostPictures), late: Int(s.latePictures), shown: Int(s.displayedPictures))
                    TraceFile.write("vlc", "\(TraceFile.statsWindow) s: \(now.decoded - last.decoded) decoded, \(now.shown - last.shown) shown, \(now.lost - last.lost) dropped, \(now.late - last.late) late; \(String(format: "%.1f", Double(s.demuxBitrate) * 8)) Mb/s; rate \(self.player.rate)")
                    last = now
                }
                self.watchDecoder(decoded: Int(s.decodedVideo), bitrate: Double(s.demuxBitrate) * 8)
                self.stats.droppedFrames = Int(s.lostPictures)
                Metrics.shared.record(.droppedFrames, value: Double(s.lostPictures))
                self.stats.decodedFrames = Int(s.decodedVideo)
                if s.demuxBitrate > 0 { self.stats.bitrateMbps = Double(s.demuxBitrate) * 8 }     // bytes/µs → Mb/s
            }
        }
    }

    @ObservationIgnored private var decoderStall: (decoded: Int, seconds: Int) = (0, 0)

    /// VideoToolbox can turn a stream down — real DivX, some broadcast H.264:
    /// "bad data", the session restarted again and again, and nothing shown
    /// while the file kept arriving. Playing, data coming in, and not one
    /// frame decoded in 4 s: the item again from where it is, decoded in
    /// software (once; FFmpeg managed every such file on an Apple TV 4K).
    private func watchDecoder(decoded: Int, bitrate: Double) {
        guard !softwareDecode, !Self.decodesInSoftware(plan), status == .playing, plan?.mediaSource.videoStream != nil else { decoderStall = (decoded, 0); return }
        if decoded != decoderStall.decoded || bitrate < 0.2 { decoderStall = (decoded, 0); return }
        decoderStall.seconds += 1
        guard decoderStall.seconds >= 4, var next = plan else { return }
        softwareDecode = true
        let at = max(currentTime, startTarget ?? .zero)
        TraceFile.write("vlc", "no frames decoded in 4 s with data arriving: the hardware decoder turned it down — again in software from \(Int(at.seconds)) s")
        Self.log.notice("VideoToolbox decoded nothing in 4 s: software decode from \(at.seconds, privacy: .public) s")
        next.startPosition = at
        statsTask?.cancel()
        player.stop()
        Task { [weak self] in try? await self?.load(next, autoplay: true) }
    }

    /// What VLC draws into (diagnostics): its views and layers and their
    /// pixel scale. `-vlcSurfaceScale <s>` sets that scale (test: drawing
    /// at 1080p on a 4K screen, the TV scaling up).
    private func describeSurface() {
        #if canImport(UIKit)
        let forced = UserDefaults.standard.object(forKey: "vlcSurfaceScale") as? Double
        func walk(_ v: UIView, _ depth: Int) {
            if let forced {
                v.contentScaleFactor = forced
                v.layer.contentsScale = forced
                v.layer.sublayers?.forEach { $0.contentsScale = forced }
            }
            TraceFile.write("vlc", String(repeating: "  ", count: depth) + "\(type(of: v)) \(Int(v.bounds.width))x\(Int(v.bounds.height)) @\(v.contentScaleFactor) layer \(type(of: v.layer))")
            v.subviews.forEach { walk($0, depth + 1) }
        }
        walk(surface, 0)
        #endif
    }

    // MARK: Helpers

    static func duration(_ time: VLCTime?) -> Duration? {
        guard let ms = time?.value?.int64Value else { return nil }
        return .milliseconds(ms)
    }

    /// From Jellyfin's stream metadata (drives the HUD; display-mode
    /// matching reads the same metadata directly).
    static func formatInfo(_ stream: MediaStream?) -> VideoFormatInfo? {
        guard let stream else { return nil }
        let t = stream.videoRangeType ?? ""
        let range: DynamicRange = t.hasPrefix("DOVI") ? .dolbyVision : t == "HDR10Plus" ? .hdr10Plus : t == "HDR10" ? .hdr10 : t == "HLG" ? .hlg : .sdr
        let codec = (stream.codec ?? "?").lowercased()
        return VideoFormatInfo(
            codec: codec, width: stream.width ?? 0, height: stream.height ?? 0,
            frameRate: stream.realFrameRate ?? stream.averageFrameRate ?? 24, dynamicRange: range,
            bitDepth: stream.bitDepth ?? 8, hardwareDecoded: ["h264", "hevc"].contains(codec), dolbyVisionProfile: stream.dvProfile
        )
    }

    public func setFillsScreen(_ fill: Bool) {
        player.videoFitMode = fill ? .larger : .smaller
    }
}

public enum VLCEngineError: Error, LocalizedError {
    case cannotOpen, timedOut, playbackFailed
    public var errorDescription: String? {
        switch self {
        case .cannotOpen: "This stream can't be opened."
        case .timedOut: "It took too long to start."
        case .playbackFailed: "This file couldn't be played."
        }
    }
}

/// VLCMediaThumbnailer callbacks → main.
private final class ThumbnailEvents: NSObject, VLCMediaThumbnailerDelegate, @unchecked Sendable {
    nonisolated(unsafe) var done: (@MainActor (CGImage?) -> Void)?

    func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.done?(nil) } }
    }

    func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        nonisolated(unsafe) let image = thumbnail
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.done?(image) } }
    }
}

/// VLCKit 4 calls its delegate on its own event thread; hop to main.
private final class Events: NSObject, VLCMediaPlayerDelegate, @unchecked Sendable {
    nonisolated(unsafe) weak var engine: VLCEngine?

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.engine?.stateChanged(newState) }
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.engine?.timeChanged() }
        }
    }
}
#endif
