public import CoreGraphics
public import CoreMedia
import Foundation
public import Instrumentation
public import JellyfinAPI
public import Observation
#if canImport(UIKit)
public import UIKit
/// The view a player draws into: UIKit on TV/iPhone/iPad, AppKit on the Mac.
public typealias PlatformView = UIView
#else
public import AppKit
public typealias PlatformView = NSView
#endif

public enum PlaybackStatus: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case failed(String)

    public var isActive: Bool { self == .playing || self == .buffering }
}

public enum DynamicRange: String, Sendable, Codable, Hashable {
    case sdr = "SDR"
    case hdr10 = "HDR10"
    case hdr10Plus = "HDR10+"
    case hlg = "HLG"
    case dolbyVision = "Dolby Vision"
}

/// What's actually being decoded and shown — drives display-mode matching
/// (refresh rate + dynamic range) and the stats HUD.
public struct VideoFormatInfo: Sendable, Equatable {
    public var codec: String
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var dynamicRange: DynamicRange
    public var bitDepth: Int
    public var hardwareDecoded: Bool
    public var dolbyVisionProfile: Int?

    public init(codec: String, width: Int, height: Int, frameRate: Double, dynamicRange: DynamicRange, bitDepth: Int, hardwareDecoded: Bool, dolbyVisionProfile: Int? = nil) {
        self.codec = codec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.dynamicRange = dynamicRange
        self.bitDepth = bitDepth
        self.hardwareDecoded = hardwareDecoded
        self.dolbyVisionProfile = dolbyVisionProfile
    }

    public var summary: String {
        let res = height >= 2000 ? "4K" : height >= 1000 ? "1080p" : height >= 700 ? "720p" : "\(height)p"
        let fps = frameRate.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(frameRate)) : frameRate.formatted(.number.precision(.fractionLength(3)))
        return "\(codec.uppercased()) \(res) \(fps)fps \(dynamicRange.rawValue) · \(hardwareDecoded ? "HW" : "SW")"
    }
}

public struct MediaTrack: Sendable, Identifiable, Hashable {
    /// Jellyfin stream index where known (stable across engines).
    public var id: Int
    public var title: String
    public var language: String?
    public var codec: String?
    public var isDefault: Bool
    public var isForced: Bool
    public var detail: String?

    public init(id: Int, title: String, language: String?, codec: String?, isDefault: Bool, isForced: Bool = false, detail: String? = nil) {
        self.id = id
        self.title = title
        self.language = language
        self.codec = codec
        self.isDefault = isDefault
        self.isForced = isForced
        self.detail = detail
    }
}

/// Live engine statistics for the HUD and perf tests.
public struct EngineStats: Sendable, Equatable {
    public var engineName: String = ""
    public var method: String = ""
    public var video: String = "—"
    public var audio: String = "—"
    public var bitrateMbps: Double?
    public var bufferedSeconds: Double = 0
    public var droppedFrames: Int = 0
    public var decodedFrames: Int = 0
    public var stalls: Int = 0
    public var notes: [String] = []

    public init() {}
}

/// One player interface, two backends (AVPlayer, VLCKit). The UI asks for
/// play, pause, seek, rate and track selection and never knows which backend
/// is active. Track ids are always Jellyfin stream indexes.
@MainActor
public protocol PlayerEngine: AnyObject, Observable {
    var kind: EngineKind { get }
    var status: PlaybackStatus { get }
    var currentTime: Duration { get }
    /// The playhead read from the backend right now (`currentTime` is only
    /// refreshed a few times a second).
    var playheadNow: Duration { get }
    var duration: Duration? { get }
    var rate: Float { get }
    var audioTracks: [MediaTrack] { get }
    var selectedAudioTrack: Int? { get }
    /// True when the backend draws subtitles itself (VLCKit: ASS, PGS, …);
    /// false when the player overlays text cues (AVPlayer + WebVTT).
    var rendersSubtitles: Bool { get }
    /// The subtitle track the backend reports as showing (read back from the
    /// backend, not what was asked for). nil = none, or not applicable.
    var activeSubtitleTrack: String? { get }
    var videoFormat: VideoFormatInfo? { get }
    var stats: EngineStats { get }
    /// When the first frame at the latest seek target was ready (benchmarks).
    var lastSeekFrameAt: ContinuousClock.Instant? { get }
    /// The backend's video surface.
    var videoView: PlatformView { get }
    /// Picture in Picture, where this backend can float its picture on this
    /// device; nil where it can't (the TV; VLCKit on the Mac).
    var pictureInPicture: PictureInPicture? { get }

    /// Opens and buffers up to the first frame. With `autoplay: false` the
    /// clock is held until `play()` — so the player prepares *while* the TV
    /// switches display mode, instead of after.
    func load(_ plan: PlaybackPlan, autoplay: Bool) async throws
    func play()
    func pause()
    func seek(to time: Duration) async
    /// How rapid seeks (a burst of skip presses) should be fed: true = one at
    /// a time, then straight to the latest target (AVPlayer: a superseded
    /// seek restarts its fetch/decode); false = latest target immediately
    /// (VLCKit drops superseded seeks cheaply).
    var prefersSerialSeeks: Bool { get }
    func setRate(_ rate: Float)
    func stop()
    /// 0…1 output volume (the sleep timer fades out with it).
    func setVolume(_ volume: Float)
    func selectAudio(_ streamIndex: Int) async
    /// A small frame near `time` for the scrub preview (when the server has
    /// no trickplay images). May be approximate; nil if unavailable.
    func thumbnail(at time: Duration) async -> CGImage?
    /// nil = off. `external` is the server URL for a sidecar subtitle file.
    /// Backends that don't render subtitles ignore it.
    func selectSubtitle(_ stream: MediaStream?, external: URL?) async
    /// Fill the screen (cropping the picture's edges) or show all of it.
    func setFillsScreen(_ fill: Bool)
}

extension PlayerEngine {
    public func load(_ plan: PlaybackPlan) async throws { try await load(plan, autoplay: true) }
}

extension Duration {
    public var cmTime: CMTime { CMTime(seconds: seconds, preferredTimescale: 90_000) }

    public init(_ time: CMTime) {
        self = time.isNumeric ? .nanoseconds(Int64(time.seconds * 1e9)) : .zero
    }

    /// "1:02:03" / "2:03"
    public var clockString: String {
        let total = Int(max(0, seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? "\(h):\(m < 10 ? "0" : "")\(m):\(s < 10 ? "0" : "")\(s)" : "\(m):\(s < 10 ? "0" : "")\(s)"
    }
}
