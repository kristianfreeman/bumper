#if os(macOS)                    // in-process view tests: the Mac's `swift test`
import AppKit
import CoreGraphics
import JellyfinAPI
import Observation
import PlaybackCore

/// A backend that decodes nothing: the player's side of the engine (loading,
/// playing, paused, the playhead, Picture in Picture) is real; the picture
/// is an empty view and the test moves the clock. So the player's screens —
/// chrome, chapters, the split, slow starts — are checked in milliseconds,
/// with no media and no AVPlayer or VLCKit.
@Observable
final class FakeEngine: PlayerEngine {
    let kind: EngineKind
    private(set) var status: PlaybackStatus = .idle
    var currentTime: Duration = .zero
    var playheadNow: Duration { currentTime }
    private(set) var duration: Duration?
    private(set) var rate: Float = 1
    var audioTracks: [MediaTrack] = []
    private(set) var selectedAudioTrack: Int?
    /// As the real ones: VLCKit draws subtitles itself, AVPlayer leaves them to the overlay.
    var rendersSubtitles: Bool { kind == .vlc }
    /// The subtitle it's drawing (VLCKit), by its title.
    private(set) var activeSubtitleTrack: String?
    /// Every subtitle it was asked for, in turn (nil: off).
    @ObservationIgnored private(set) var subtitleRequests: [MediaStream?] = []
    /// As VLCKit does with an MKV's default ASS: draws the file's first
    /// subtitle on opening, asked for nothing (until asked for something).
    @ObservationIgnored var picksItsOwnSubtitle = false
    @ObservationIgnored private(set) var drawnSubtitleStream: Int?
    var videoFormat: VideoFormatInfo?
    var stats = EngineStats()
    @ObservationIgnored private(set) var lastSeekFrameAt: ContinuousClock.Instant?
    @ObservationIgnored let videoView: PlatformView = NSView()
    let prefersSerialSeeks = false
    /// Where the picture could float: the test says when the system would
    /// allow it (`pictureInPicture?.setPossible`); set nil for a backend
    /// that can't float at all.
    @ObservationIgnored var pictureInPicture: PictureInPicture?

    /// A slow start: `load` waits here until `finishLoading()`.
    @ObservationIgnored var holdsLoading = false
    @ObservationIgnored private var loading: CheckedContinuation<Void, Never>?
    /// What it was asked to open.
    @ObservationIgnored private(set) var plan: PlaybackPlan?

    init(kind: EngineKind) {
        self.kind = kind
        stats.engineName = "Fake"
        // As the system does: asked to float, it floats; asked back, it stops.
        pictureInPicture = PictureInPicture(start: { [weak self] in self?.pictureInPicture?.started() },
                                            stop: { [weak self] in self?.pictureInPicture?.stopped() })
    }

    func load(_ plan: PlaybackPlan, autoplay: Bool) async throws {
        self.plan = plan
        status = .loading
        duration = plan.item.runtime
        currentTime = plan.startPosition
        if picksItsOwnSubtitle, rendersSubtitles, let first = plan.mediaSource.subtitleStreams.first {
            activeSubtitleTrack = first.displayTitle
            drawnSubtitleStream = first.index
        }
        if holdsLoading { await withCheckedContinuation { loading = $0 } }
        status = autoplay ? .playing : .paused
    }

    func finishLoading() {
        loading?.resume()
        loading = nil
    }

    func play() { status = .playing }
    /// The item played to its end (what the player waits for to go on).
    func reachEnd() { currentTime = duration ?? currentTime; status = .ended }
    func pause() { status = .paused }
    func seek(to time: Duration) async {
        currentTime = time
        lastSeekFrameAt = .now
    }
    func setRate(_ rate: Float) { self.rate = rate }
    func stop() {
        finishLoading()
        status = .idle
    }
    func setVolume(_ volume: Float) {}
    func selectAudio(_ streamIndex: Int) async { selectedAudioTrack = streamIndex }
    func thumbnail(at time: Duration) async -> CGImage? { nil }
    func selectSubtitle(_ stream: MediaStream?, external: URL?) async {
        subtitleRequests.append(stream)
        if rendersSubtitles {
            activeSubtitleTrack = stream.map { $0.displayTitle ?? "#\($0.index)" }
            drawnSubtitleStream = stream?.index
        }
    }
    func setFillsScreen(_ fill: Bool) {}
}
#endif
