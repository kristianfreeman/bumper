public import Foundation
public import JellyfinAPI

public enum EngineKind: String, Sendable, Codable, Hashable {
    /// AVPlayer — only for MP4/M4V/MOV/HLS carrying H.264/HEVC with
    /// AAC/AC-3/E-AC-3 and no subtitles or WebVTT. It exists for Picture in
    /// Picture, AirPlay and system Dolby Vision.
    case native
    /// VLCKit — everything else: MKV, ASS/SSA, PGS, DTS, TrueHD, MPEG-2,
    /// VC-1, AV1, … and any item AVPlayer fails on.
    case vlc
}

public enum PlayMethod: String, Sendable, Codable, Hashable {
    case directPlay = "DirectPlay"
    case directStream = "DirectStream"
    case transcode = "Transcode"
}

/// Everything an engine needs to start playing, plus *why* we chose it
/// (surfaced in the stats HUD — "why is this transcoding?" should never be a
/// mystery).
public struct PlaybackPlan: Sendable, Identifiable {
    public var id: String { playSessionId ?? item.id }

    public var item: BaseItem
    public var mediaSource: MediaSource
    public var url: URL
    public var engine: EngineKind
    public var method: PlayMethod
    public var playSessionId: String?
    public var startPosition: Duration
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?
    public var reasons: [String]

    public init(item: BaseItem, mediaSource: MediaSource, url: URL, engine: EngineKind, method: PlayMethod, playSessionId: String?, startPosition: Duration, audioStreamIndex: Int?, subtitleStreamIndex: Int?, reasons: [String]) {
        self.item = item
        self.mediaSource = mediaSource
        self.url = url
        self.engine = engine
        self.method = method
        self.playSessionId = playSessionId
        self.startPosition = startPosition
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.reasons = reasons
    }

    public var selectedAudio: MediaStream? {
        mediaSource.audioStreams.first { $0.index == audioStreamIndex } ?? mediaSource.audioStreams.first
    }
}
