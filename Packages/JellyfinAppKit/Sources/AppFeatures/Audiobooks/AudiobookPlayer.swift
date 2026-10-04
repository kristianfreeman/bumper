#if os(tvOS)
import AppCore
import AVFoundation
import DesignSystem
import Instrumentation
import JellyfinAPI
import MediaPlayer
import Observation
import PlaybackCore
import UIKit

/// Plays one audiobook: parts back to back, chapters, speed, Smart Speed,
/// the sleep timer, progress to Jellyfin (so Resume works everywhere) and
/// the system's Now Playing (Control Center, the remote's buttons).
@MainActor
@Observable
final class AudiobookPlayer {
    let book: Audiobook
    /// Book seconds being heard.
    private(set) var position: Double = 0
    private(set) var isPlaying = false
    private(set) var isBuffering = true
    private(set) var finished = false
    private(set) var error: String?
    /// Silence removed by Smart Speed this session.
    var savedSeconds: Double { savedEarlier + savedThisPart }
    var rate: Double { didSet { settings.audiobookRate = rate; pipeline?.setRate(Float(rate)); updateNowPlaying() } }
    var smartSpeed: Bool { didSet { settings.smartSpeed = smartSpeed; pipeline?.setSmartSpeed(smartSpeed) } }

    static let speeds: [Double] = [0.8, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0, 2.5, 3.0]

    @ObservationIgnored private let client: JellyfinClient
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let sleepTimer: SleepTimer
    @ObservationIgnored private var pipeline: AudiobookPipeline?
    @ObservationIgnored private var part = 0
    @ObservationIgnored private var savedEarlier = 0.0
    private var savedThisPart = 0.0
    @ObservationIgnored private var lastReport: ContinuousClock.Instant?
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var sleepChapter: Int?
    /// Press → first sound (trace), per open.
    @ObservationIgnored private var openedAt: (ContinuousClock.Instant, Double)?

    init(book: Audiobook, client: JellyfinClient, settings: AppSettings, sleepTimer: SleepTimer) {
        self.book = book
        self.client = client
        self.settings = settings
        self.sleepTimer = sleepTimer
        rate = settings.audiobookRate
        smartSpeed = settings.smartSpeed
    }

    // MARK: Chapters

    var chapterIndex: Int? { book.chapterIndex(at: position) }
    var chapter: Audiobook.Chapter? { chapterIndex.map { book.chapters[$0] } }
    /// The chapter's span, or the whole book when it has none.
    var chapterRange: ClosedRange<Double> { chapterIndex.map(book.chapterRange) ?? 0...book.duration }
    /// Book time left, at the current speed.
    var remainingAtSpeed: Double { max(0, book.duration - position) / max(rate, 0.1) }

    // MARK: Transport

    func start(at time: Double) {
        TraceFile.write("audiobook", "start \(book.id) at \(Int(time)) s, \(rate)×, Smart Speed \(smartSpeed)")
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        configureRemoteCommands()
        loadArtwork()
        open(at: time, playing: true)
        watchSleepTimer()
    }

    /// One press of Play/Pause can arrive twice (SwiftUI and Now Playing).
    @ObservationIgnored private var lastToggle: ContinuousClock.Instant?

    func togglePlayPause() {
        if let last = lastToggle, last.duration(to: .now) < .milliseconds(250) { return }
        lastToggle = .now
        isPlaying ? pause() : play()
    }

    func play() {
        if finished { finished = false; open(at: 0, playing: true); return }
        pipeline?.play()
        isPlaying = true
        report(force: true)
    }

    func pause() {
        pipeline?.pause()
        isPlaying = false
        report(force: true)
    }

    func skip(by seconds: Double) { seek(to: position + seconds) }

    func seek(to time: Double) {
        let t = min(max(0, time), max(0, book.duration - 0.5))
        let (index, offset) = book.locate(t)
        position = t
        if index == part, let pipeline {
            pipeline.seek(to: offset)
            finished = false
        } else {
            open(at: t, playing: isPlaying || pipeline == nil)
        }
        updateNowPlaying()
    }

    /// Back: to the start of this chapter, or the previous one when already near it.
    func previousChapter() {
        guard let i = chapterIndex else { skip(by: -30); return }
        let start = book.chapters[i].start
        seek(to: position - start > 3 || i == 0 ? start : book.chapters[i - 1].start)
    }

    func nextChapter() {
        guard let i = chapterIndex, i + 1 < book.chapters.count else { return }
        seek(to: book.chapters[i + 1].start)
    }

    func stop() {
        report(force: true, stopped: true)
        pipeline?.stop()
        pipeline = nil
        sleepTask?.cancel()
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Parts

    private func open(at time: Double, playing: Bool) {
        let (index, offset) = book.locate(time)
        if pipeline != nil { report(force: true, stopped: true) }
        pipeline?.stop()
        savedEarlier += savedThisPart
        savedThisPart = 0
        part = index
        position = time
        let itemId = book.parts[index].id
        let client = client
        let p = AudiobookPipeline(streamURL: { t in client.audiobookStreamURL(itemId: itemId, start: t) }, smartSpeed: smartSpeed)
        p.setRate(Float(rate))
        p.onUpdate = { [weak self] state in
            DispatchQueue.main.async { self?.update(state, from: p) }
        }
        pipeline = p
        openedAt = (.now, time)
        isPlaying = playing
        isBuffering = true
        p.start(at: offset, playing: playing)
        Task { try? await client.reportPlaybackStart(progressReport(paused: !playing)) }
    }

    private func update(_ state: AudiobookPipeline.State, from source: AudiobookPipeline) {
        guard source === pipeline else { return }                     // a part we've moved on from
        position = book.partStart(part) + state.position
        if let (at, from) = openedAt, position > from + 0.05 {
            openedAt = nil
            TraceFile.write("audiobook", "first sound in \(Int(at.duration(to: .now).milliseconds) - 50) ms at \(Int(from)) s")
        }
        isBuffering = state.buffering && isPlaying
        savedThisPart = state.savedSeconds
        if let message = state.error, error == nil {
            error = message
            TraceFile.write("audiobook", "error: \(message)")
        }
        if state.ended {
            if part + 1 < book.parts.count {
                open(at: book.partStart(part + 1), playing: true)     // next part
            } else if !finished {
                TraceFile.write("audiobook", "finished; Smart Speed saved \(Int(savedSeconds)) s")
                finished = true
                isPlaying = false
                report(force: true, stopped: true)
            }
        }
        report()
        updateNowPlaying()
    }

    // MARK: Sleep timer

    private func watchSleepTimer() {
        sleepTask?.cancel()
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.checkSleepTimer()
            }
        }
    }

    private func checkSleepTimer() {
        switch sleepTimer.mode {
        case .off:
            sleepChapter = nil
            pipeline?.setVolume(1)
        case .endOfItem:                                             // for a book: the end of this chapter
            if sleepChapter == nil { sleepChapter = chapterIndex ?? -1 }
            if let started = sleepChapter, isPlaying, (chapterIndex ?? -1) != started || position >= chapterRange.upperBound - 0.3 {
                pause()
                sleepTimer.reset()
            }
        case .minutes:
            if let v = sleepTimer.fadeVolume { pipeline?.setVolume(v) }
            if sleepTimer.hasExpired, isPlaying {
                pause()
                pipeline?.setVolume(1)
                sleepTimer.reset()
            }
        }
    }

    // MARK: Jellyfin progress

    private func progressReport(paused: Bool) -> PlaybackProgressReport {
        let offset = position - book.partStart(part)
        return PlaybackProgressReport(itemId: book.parts[part].id, mediaSourceId: book.parts[part].id, playSessionId: nil,
                                      positionTicks: Int64(max(0, offset) * Double(BaseItem.ticksPerSecond)), isPaused: paused,
                                      playMethod: "Transcode", audioStreamIndex: nil, subtitleStreamIndex: nil)
    }

    private func report(force: Bool = false, stopped: Bool = false) {
        if !force, let last = lastReport, last.duration(to: .now) < .seconds(10) { return }
        lastReport = .now
        let report = progressReport(paused: !isPlaying)
        let client = client
        Task {
            if stopped { try? await client.reportPlaybackStopped(report) } else { try? await client.reportPlaybackProgress(report) }
        }
    }

    // MARK: Now Playing

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapter?.title ?? book.title,
            MPMediaItemPropertyAlbumTitle: book.title,
            MPMediaItemPropertyPlaybackDuration: book.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let author = book.author { info[MPMediaItemPropertyArtist] = author }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork() {
        guard let source = ArtworkSource.resolve(book.cover, .poster) else { return }
        let request = source.request(client: client, pixelWidth: 600)
        Task {
            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            artwork = Self.artwork(UIImage(cgImage: image))
            updateNowPlaying()
        }
    }

    /// MediaPlayer calls the image handler on its own queue: it must not be
    /// main-actor isolated (this module's default), or it traps.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.changePlaybackRateCommand.supportedPlaybackRates = Self.speeds.map { NSNumber(value: $0) }
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (MPRemoteCommandEvent) -> Void) {
            let target = command.addTarget { event in
                MainActor.assumeIsolated { action(event) }
                return .success
            }
            remoteTargets.append((command, target))
        }
        on(center.togglePlayPauseCommand) { [weak self] _ in self?.togglePlayPause() }
        on(center.playCommand) { [weak self] _ in self?.play() }
        on(center.pauseCommand) { [weak self] _ in self?.pause() }
        on(center.skipForwardCommand) { [weak self] _ in self?.skip(by: 30) }
        on(center.skipBackwardCommand) { [weak self] _ in self?.skip(by: -15) }
        on(center.nextTrackCommand) { [weak self] _ in self?.nextChapter() }
        on(center.previousTrackCommand) { [weak self] _ in self?.previousChapter() }
        on(center.changePlaybackRateCommand) { [weak self] event in
            if let e = event as? MPChangePlaybackRateCommandEvent { self?.rate = Double(e.playbackRate) }
        }
        on(center.changePlaybackPositionCommand) { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: e.positionTime) }
        }
    }
}
#endif
