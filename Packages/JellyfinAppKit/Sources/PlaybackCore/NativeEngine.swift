public import AVFoundation
public import CoreMedia
public import Observation
public import QuartzCore
#if canImport(UIKit)
public import UIKit
#else
public import AppKit
#endif
import Instrumentation
public import JellyfinAPI
import AVKit
import os

/// The AVPlayer backend: MP4/MOV/HLS with H.264/HEVC and AAC/AC-3/E-AC-3
/// only (see PlaybackPlanner) — for Picture in Picture, AirPlay and system
/// Dolby Vision. Subtitles (WebVTT) are overlaid by the player.
@MainActor
@Observable
public final class NativeEngine: PlayerEngine {
    public let kind: EngineKind = .native
    public private(set) var status: PlaybackStatus = .idle
    @ObservationIgnored public private(set) var lastSeekFrameAt: ContinuousClock.Instant?
    public var playheadNow: Duration { Duration(player.currentTime()) }
    public private(set) var currentTime: Duration = .zero
    public private(set) var duration: Duration?
    public private(set) var audioTracks: [MediaTrack] = []
    public private(set) var selectedAudioTrack: Int?
    public private(set) var videoFormat: VideoFormatInfo?
    public private(set) var stats = EngineStats()
    public private(set) var rate: Float = 1
    public let rendersSubtitles = false
    public let prefersSerialSeeks = true
    public var activeSubtitleTrack: String? { nil }

    @ObservationIgnored public let player = AVPlayer()
    @ObservationIgnored private let surface = PlayerLayerView()
    public var videoView: PlatformView { surface }
    private var playerLayer: AVPlayerLayer { surface.playerLayer }
    /// On the player's own layer (iPhone, iPad, Mac; the TV has none).
    @ObservationIgnored public private(set) var pictureInPicture: PictureInPicture?
    #if os(iOS) || os(macOS)
    @ObservationIgnored private var floating: NativeFloating?
    #endif
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var firstFrameSpan: Span?
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var metricsTask: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var plan: PlaybackPlan?

    private static let log = Perf.logger("native-engine")

    public init() {
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        player.automaticallyWaitsToMinimizeStalling = true
        player.appliesMediaSelectionCriteriaAutomatically = false
        player.isMuted = Silence.on
        stats.engineName = "AVPlayer"
        #if os(iOS) || os(macOS)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let floating = NativeFloating(layer: playerLayer)
            self.floating = floating
            pictureInPicture = floating.pip
        }
        #endif
    }

    public func load(_ plan: PlaybackPlan, autoplay: Bool) async throws {
        self.plan = plan
        status = .loading
        firstFrameSpan = Span(.timeToFirstFrame)
        stats.method = plan.method.rawValue
        stats.notes = plan.reasons

        let asset = AVURLAsset(url: plan.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        // Let AVFoundation pick the forward buffer; it's adaptive to bandwidth.
        item.preferredForwardBufferDuration = 0
        #if os(tvOS)
        // AVKit category method: present on Apple TV hardware, missing in the
        // simulator (where calling it throws "unrecognized selector").
        if item.responds(to: NSSelectorFromString("setExternalMetadata:")) {
            item.externalMetadata = Self.externalMetadata(for: plan.item)
        }
        #endif

        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            do {
                for try await event in item.allMetrics() {
                    self?.handle(event)
                }
            } catch {}
        }

        observe(item)
        player.replaceCurrentItem(with: item)

        if plan.startPosition > .zero {
            // Keyframe-tolerant seek: lands on the GOP boundary up to 3 s
            // earlier instead of decoding forward to an exact frame. For a
            // resume, nobody notices 2 s; everybody notices a slow start.
            await player.seek(to: plan.startPosition.cmTime, toleranceBefore: CMTime(seconds: 3, preferredTimescale: 600), toleranceAfter: .zero)
        }
        // Not playing yet still loads + buffers. (preroll(atRate:) measured no
        // faster on device, and made cold starts slower.)
        if autoplay { player.play() }

        Task { await self.loadAssetDetails(asset, plan: plan) }
    }

    private func loadAssetDetails(_ asset: AVURLAsset, plan: PlaybackPlan) async {
        if let group = try? await asset.loadMediaSelectionGroup(for: .audible) {
            audioGroup = group
            // Options are in file order, as are Jellyfin's audio streams:
            // pair them up so ids are Jellyfin stream indexes.
            let streams = plan.mediaSource.audioStreams.filter { $0.isExternal != true }
            audioTracks = group.options.enumerated().map { idx, option in
                let stream = idx < streams.count ? streams[idx] : nil
                return MediaTrack(id: stream?.index ?? idx, title: stream?.displayTitle ?? option.displayName, language: option.extendedLanguageTag ?? option.locale?.identifier, codec: stream?.codec, isDefault: idx == 0)
            }
            selectedAudioTrack = audioTracks.first?.id
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (descriptions, fps) = try? await track.load(.formatDescriptions, .nominalFrameRate),
           let desc = descriptions.first {
            videoFormat = Self.formatInfo(desc, fps: Double(fps), stream: plan.mediaSource.videoStream)
        } else if let stream = plan.mediaSource.videoStream {
            // HLS: no asset tracks up front; fall back to server metadata.
            videoFormat = Self.formatInfo(nil, fps: stream.realFrameRate ?? stream.averageFrameRate ?? 24, stream: stream)
        }
        stats.video = videoFormat?.summary ?? "—"
        if let audio = plan.selectedAudio {
            stats.audio = "\(audio.displayTitle ?? audio.codec ?? "") · system decoder"
        }
    }

    private func observe(_ item: AVPlayerItem) {
        observations.removeAll()
        if let timeObserver { player.removeTimeObserver(timeObserver) }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = Duration(time)
                if let item = self.player.currentItem {
                    if let range = item.loadedTimeRanges.last?.timeRangeValue {
                        self.stats.bufferedSeconds = max(0, (range.end - time).seconds)
                    }
                }
            }
        }

        statsTask?.cancel()
        statsTask = Task { [weak self] in
            var tick = 0
            var last = (dropped: 0, stalls: 0)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let (dropped, bitrate) = await Self.accessLogStats(item)
                guard let self else { return }
                self.stats.droppedFrames = dropped
                if bitrate > 0 { self.stats.bitrateMbps = bitrate / 1e6 }
                // Every few seconds in the trace, like VLCKit's (the playback matrix reads both).
                tick += 1
                if tick % TraceFile.statsWindow == 0 {
                    TraceFile.write("native", "\(TraceFile.statsWindow) s: \(dropped - last.dropped) dropped, \(self.stats.stalls - last.stalls) stalls; \(String(format: "%.1f", bitrate / 1e6)) Mb/s; rate \(self.player.rate)")
                    last = (dropped, self.stats.stalls)
                }
            }
        }

        observations.append(item.observe(\.status) { [weak self] item, _ in
            let status = item.status
            let error = item.error?.localizedDescription
            let duration = item.duration
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    if duration.isNumeric { self.duration = Duration(duration) }
                case .failed:
                    self.status = .failed(error ?? "Playback failed")
                    Self.log.error("AVPlayerItem failed: \(error ?? "?", privacy: .public)")
                    TraceFile.write("native", "AVPlayerItem failed: \(error ?? "?")")
                default: break
                }
            }
        })
        observations.append(player.observe(\.timeControlStatus) { [weak self] player, _ in
            let tcs = player.timeControlStatus
            Task { @MainActor in
                guard let self, case .failed = self.status else {
                    self?.status = switch tcs {
                    case .playing: .playing
                    case .paused: (self?.status == .ended ? .ended : .paused)
                    case .waitingToPlayAtSpecifiedRate: .buffering
                    @unknown default: .buffering
                    }
                    return
                }
            }
        })
        observations.append(playerLayer.observe(\.isReadyForDisplay) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in
                guard let self, let span = self.firstFrameSpan else { return }
                let ttff = span.end()
                self.firstFrameSpan = nil
                Self.log.info("First frame in \(ttff.milliseconds, privacy: .public) ms")
                TraceFile.write("native", "First frame in \(Int(ttff.milliseconds)) ms")
            }
        })
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.status = .ended }
        }
    }

    private func handle(_ event: AVMetricEvent) {
        switch event {
        case let e as AVMetricPlayerItemInitialLikelyToKeepUpEvent:
            Perf.event("native.likelyToKeepUp", "\(e.timeTaken)")
        case is AVMetricPlayerItemStallEvent:
            stats.stalls += 1
            Metrics.shared.record(.rebuffer, value: 1)
        case let e as AVMetricPlayerItemSeekDidCompleteEvent:
            Perf.event("native.seekComplete", e.didSeekInBuffer ? "in-buffer" : "network")
        default: break
        }
    }

    public func play() { player.playImmediately(atRate: rate) }
    public func pause() { player.pause() }

    public func setRate(_ rate: Float) {
        self.rate = rate
        player.defaultRate = rate                  // what PiP's play button plays at
        if player.rate != 0 { player.rate = rate }
    }

    public func seek(to time: Duration) async {
        let span = Span(.seekLatency)
        await player.seek(to: time.cmTime, toleranceBefore: CMTime(value: 1, timescale: 2), toleranceAfter: CMTime(value: 1, timescale: 2))
        lastSeekFrameAt = .now                 // seek completion = frame at target ready
        span.end()
        currentTime = time
    }

    public func selectAudio(_ streamIndex: Int) async {
        guard let group = audioGroup, let item = player.currentItem,
              let position = audioTracks.firstIndex(where: { $0.id == streamIndex }), position < group.options.count else { return }
        item.select(group.options[position], in: group)
        selectedAudioTrack = streamIndex
    }

    @ObservationIgnored private var thumbnailAsset: AVURLAsset?

    /// Scrub previews from a second asset on the same URL: small, keyframe-
    /// tolerant (fast) and independent of playback.
    public func thumbnail(at time: Duration) async -> CGImage? {
        guard let plan else { return nil }
        let asset = thumbnailAsset ?? AVURLAsset(url: plan.url)
        thumbnailAsset = asset
        return await Self.frame(of: asset, at: time.cmTime)
    }

    private nonisolated static func frame(of asset: AVURLAsset, at time: CMTime) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 480, height: 270)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 3, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    /// WebVTT is overlaid by the player; nothing to do here.
    public func selectSubtitle(_ stream: MediaStream?, external: URL?) async {}

    public func setFillsScreen(_ fill: Bool) {
        playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    public func setVolume(_ volume: Float) { player.volume = volume }

    public func stop() {
        if pictureInPicture?.isActive == true { pictureInPicture?.stop() }
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.removeAll()
        metricsTask?.cancel()
        metricsTask = nil
        statsTask?.cancel()
        statsTask = nil
        player.replaceCurrentItem(with: nil)
        status = .idle
    }

    // MARK: Helpers

    /// Dropped frames + indicated bitrate. tvOS 27 fetches the log async;
    /// tvOS 26 reads it synchronously (deprecated in 27, fine on 26).
    static func accessLogStats(_ item: AVPlayerItem) async -> (Int, Double) {
        if #available(tvOS 27, iOS 27, macOS 27, *) {
            return await withCheckedContinuation { (cont: CheckedContinuation<(Int, Double), Never>) in
                item.fetchAccessLog { log in
                    let event = log?.events.last
                    cont.resume(returning: (event?.numberOfDroppedVideoFrames ?? 0, event?.indicatedBitrate ?? 0))
                }
            }
        }
        let event = item.accessLog()?.events.last
        return (event?.numberOfDroppedVideoFrames ?? 0, event?.indicatedBitrate ?? 0)
    }

    static func formatInfo(_ desc: CMFormatDescription?, fps: Double, stream: MediaStream?) -> VideoFormatInfo {
        var range: DynamicRange = .sdr
        if let stream {
            let t = stream.videoRangeType ?? ""
            range = t.hasPrefix("DOVI") ? .dolbyVision : t == "HDR10Plus" ? .hdr10Plus : t == "HDR10" ? .hdr10 : t == "HLG" ? .hlg : .sdr
        }
        let dims = desc.map { CMVideoFormatDescriptionGetDimensions($0) }
        return VideoFormatInfo(
            codec: stream?.codec ?? desc.map { CMFormatDescriptionGetMediaSubType($0).fourCC } ?? "?",
            width: Int(dims?.width ?? Int32(stream?.width ?? 0)),
            height: Int(dims?.height ?? Int32(stream?.height ?? 0)),
            frameRate: fps,
            dynamicRange: range,
            bitDepth: stream?.bitDepth ?? 8,
            hardwareDecoded: true,
            dolbyVisionProfile: stream?.dvProfile
        )
    }

    static func externalMetadata(for item: BaseItem) -> [AVMetadataItem] {
        func meta(_ id: AVMetadataIdentifier, _ value: String?) -> AVMetadataItem? {
            guard let value else { return nil }
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m.copy() as? AVMetadataItem
        }
        let title = item.kind == .episode ? item.name : item.name
        let subtitle = item.kind == .episode ? [item.seriesName, item.episodeLabel].compactMap { $0 }.joined(separator: " · ") : item.productionYear.map(String.init)
        return [meta(.commonIdentifierTitle, title), meta(.iTunesMetadataTrackSubTitle, subtitle), meta(.commonIdentifierDescription, item.overview)].compactMap { $0 }
    }
}

#if os(iOS) || os(macOS)
/// The system's Picture in Picture controller on the player's layer, and
/// its delegate. Starts on its own as you leave the app while it plays
/// (iPhone, iPad; the system's setting decides).
@MainActor
private final class NativeFloating: NSObject, AVPictureInPictureControllerDelegate {
    let controller: AVPictureInPictureController
    let pip: PictureInPicture
    private var possible: NSKeyValueObservation?

    init(layer: AVPlayerLayer) {
        let controller = AVPictureInPictureController(contentSource: .init(playerLayer: layer))
        self.controller = controller
        pip = PictureInPicture(start: { controller.startPictureInPicture() }, stop: { controller.stopPictureInPicture() })
        super.init()
        controller.delegate = self
        #if os(iOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        possible = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let now = controller.isPictureInPicturePossible
            Task { @MainActor in self?.pip.setPossible(now) }
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        TraceFile.write("native", "picture in picture on")
        pip.started()
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        TraceFile.write("native", "picture in picture failed: \(error.localizedDescription)")
        pip.stopped()
    }

    /// The window's restore button: the player's screen back first, then
    /// the picture into it.
    func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            await pip.restore()
            completionHandler(true)
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        TraceFile.write("native", "picture in picture off")
        pip.stopped()
    }
}
#endif

#if canImport(UIKit)
/// A view whose backing layer *is* the AVPlayerLayer (resizes with the view).
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#else
/// The Mac's: a layer-hosting view with an AVPlayerLayer as its layer.
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    init() {
        super.init(frame: .zero)
        layer = playerLayer
        wantsLayer = true
        playerLayer.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { fatalError("not used") }
}
#endif

extension FourCharCode {
    var fourCC: String {
        let bytes = [UInt8((self >> 24) & 0xff), UInt8((self >> 16) & 0xff), UInt8((self >> 8) & 0xff), UInt8(self & 0xff)]
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
