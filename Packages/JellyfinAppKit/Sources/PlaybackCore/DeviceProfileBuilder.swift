public import JellyfinAPI

/// Builds the `DeviceProfile` we send with PlaybackInfo. The profile is how
/// we tell Jellyfin "don't transcode this, I've got it" — a precise profile is
/// the single biggest lever on start-up time and picture quality.
public struct DeviceProfileBuilder: Sendable {
    public var capabilities: DeviceCapabilities
    public var maxBitrate: Int?

    public init(capabilities: DeviceCapabilities, maxBitrate: Int?) {
        self.capabilities = capabilities
        self.maxBitrate = maxBitrate
    }

    /// Server-side range types (10.11). VLCKit gets every type with a
    /// non-Dolby-Vision layer to fall back on; pure Dolby Vision (profile 5,
    /// "DOVI") would show with wrong colours, so the server repackages those
    /// as HLS for AVPlayer — the system Dolby Vision path.
    static let vlcRangeTypes = "SDR|HDR10|HDR10Plus|HLG|DOVIWithHDR10|DOVIWithHDR10Plus|DOVIWithHLG|DOVIWithSDR|DOVIWithEL|DOVIWithELHDR10Plus"
    static let avPlayerHEVCRangeTypes = "SDR|HDR10|HDR10Plus|HLG|DOVI|DOVIWithHDR10|DOVIWithHDR10Plus|DOVIWithHLG|DOVIWithSDR"

    /// What VLCKit can Direct Play — the profile we always send, so the
    /// server never transcodes a file one of our backends can play. (Which
    /// backend plays it is decided on our side; see PlaybackPlanner.)
    public func vlcProfile() -> DeviceProfile {
        DeviceProfile(
            name: "\(clientName) (VLCKit)",
            maxStreamingBitrate: maxBitrate ?? 400_000_000,
            directPlayProfiles: [
                DirectPlayProfile(container: Codecs.vlcContainers, audio: Codecs.vlcAudio, video: Codecs.vlcVideo),
                DirectPlayProfile(container: ["mp3", "flac", "aac", "m4a", "alac", "ogg", "opus", "wav", "wma", "dsf", "dff", "ape", "wv"], audio: nil, video: nil, type: "Audio"),
            ],
            transcodingProfiles: transcodingProfiles(),
            codecProfiles: ["hevc", "av1", "h264", "vp9"].map { codec in
                CodecProfile(type: "Video", codec: codec, conditions: [ProfileCondition("EqualsAny", "VideoRangeType", Self.vlcRangeTypes)])
            },
            subtitleProfiles: ["srt", "subrip", "ass", "ssa", "vtt", "webvtt", "pgssub", "dvdsub", "dvbsub", "mov_text"].map { SubtitleProfile($0, "Embed") }
                + ["srt", "subrip", "ass", "ssa", "vtt", "webvtt", "pgssub", "sub"].map { SubtitleProfile($0, "External") }
        )
    }

    /// AVPlayer's profile: only used to re-ask the server for an HLS stream
    /// when we've decided to transcode (bitrate cap, too heavy to decode).
    public func nativeProfile() -> DeviceProfile {
        DeviceProfile(
            name: "\(clientName) (AVPlayer)",
            maxStreamingBitrate: maxBitrate ?? 400_000_000,
            directPlayProfiles: [
                DirectPlayProfile(container: Array(Codecs.avPlayerContainers).sorted(), audio: Array(Codecs.avPlayerAudio).sorted(), video: Array(Codecs.avPlayerVideo(capabilities)).sorted()),
                DirectPlayProfile(container: ["mp3", "aac", "m4a", "flac", "alac", "wav"], audio: nil, video: nil, type: "Audio"),
            ],
            transcodingProfiles: transcodingProfiles(),
            codecProfiles: [
                CodecProfile(type: "Video", codec: "h264", conditions: [
                    ProfileCondition("EqualsAny", "VideoProfile", "high|main|baseline|constrained baseline"),
                    ProfileCondition("LessThanEqual", "VideoLevel", "52"),
                    ProfileCondition("LessThanEqual", "VideoBitDepth", "8"),
                    ProfileCondition("EqualsAny", "VideoRangeType", "SDR"),
                    ProfileCondition("NotEquals", "IsInterlaced", "true"),
                ]),
                CodecProfile(type: "Video", codec: "hevc", conditions: [
                    ProfileCondition("EqualsAny", "VideoProfile", "main|main 10"),
                    ProfileCondition("LessThanEqual", "VideoLevel", "183"),
                    ProfileCondition("EqualsAny", "VideoRangeType", Self.avPlayerHEVCRangeTypes),
                    ProfileCondition("NotEquals", "IsInterlaced", "true"),
                ]),
                CodecProfile(type: "VideoAudio", codec: nil, conditions: [
                    ProfileCondition("LessThanEqual", "AudioChannels", String(capabilities.maxAudioChannels)),
                ]),
            ],
            subtitleProfiles: [
                SubtitleProfile("vtt", "Hls"),
                SubtitleProfile("webvtt", "Hls"),
                SubtitleProfile("srt", "External"),
                SubtitleProfile("subrip", "External"),
                SubtitleProfile("vtt", "External"),
                SubtitleProfile("ass", "External"),
                SubtitleProfile("ssa", "External"),
                SubtitleProfile("pgssub", "Encode"),
                SubtitleProfile("dvdsub", "Encode"),
                SubtitleProfile("dvbsub", "Encode"),
            ]
        )
    }

    /// fMP4 HLS (not TS): carries HEVC/HDR/DV and E-AC-3 Atmos losslessly.
    /// Video codec order = server preference: copy HEVC when possible, else
    /// encode HEVC (half the bits of H.264 at equal quality), else H.264.
    func transcodingProfiles() -> [TranscodingProfile] {
        var video = ["hevc", "h264"]
        if capabilities.av1Hardware { video.insert("av1", at: 0) }
        return [
            TranscodingProfile(container: "mp4", video: video, audio: ["eac3", "ac3", "aac", "alac", "flac"], protocol: "hls", maxAudioChannels: capabilities.maxAudioChannels),
            TranscodingProfile(container: "aac", type: "Audio", video: [], audio: ["aac"], protocol: "hls", maxAudioChannels: 2),
        ]
    }

    private var clientName: String { "AppleTV" }
}
