import AVFoundation
import VideoToolbox

/// What *this* Apple TV can decode and output, probed once at launch.
///
/// Probing (VideoToolbox + AVFoundation queries) rather than hard-coding per
/// model means new hardware — e.g. a future AV1-capable Apple TV — lights up
/// automatically with no app update.
public struct DeviceCapabilities: Sendable, Hashable, Codable {
    // Hardware video decode
    public var h264 = true
    public var hevc = true
    public var hevcMain10 = true
    public var av1Hardware = false
    public var vp9Hardware = false

    // Display / output
    public var hdrEligible = false
    public var maxAudioChannels = 2

    public init() {}

    public static func probe() -> DeviceCapabilities {
        var caps = DeviceCapabilities()
        caps.h264 = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
        caps.hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        caps.hevcMain10 = caps.hevc
        caps.av1Hardware = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        caps.vp9Hardware = VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9)
        caps.hdrEligible = AVPlayer.eligibleForHDRPlayback
        #if os(tvOS) || os(iOS)
        caps.maxAudioChannels = max(2, AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
        #else
        caps.maxAudioChannels = 8
        #endif
        return caps
    }

    /// Fixed capabilities for tests: an Apple TV 4K (3rd gen) on a Dolby
    /// Vision TV with a 7.1 receiver.
    public static let appleTV4KReference: DeviceCapabilities = {
        var c = DeviceCapabilities()
        c.hdrEligible = true
        c.maxAudioChannels = 8
        return c
    }()
}

/// Codec/container vocabularies, using Jellyfin's (ffprobe's) names.
public enum Codecs {
    // MARK: AVPlayer route (all must hold; see PlaybackPlanner)

    public static let avPlayerContainers: Set<String> = ["mp4", "m4v", "mov"]
    public static let avPlayerAudio: Set<String> = ["aac", "ac3", "eac3"]
    public static let avPlayerSubtitles: Set<String> = ["vtt", "webvtt"]

    public static func avPlayerVideo(_ caps: DeviceCapabilities) -> Set<String> {
        caps.hevc ? ["h264", "hevc"] : ["h264"]
    }

    // MARK: VLCKit (what we declare as Direct Play)

    public static let vlcContainers: [String] = [
        "mkv", "webm", "mp4", "m4v", "mov", "avi", "ts", "mpegts", "m2ts", "mts", "flv", "ogg", "ogv",
        "wmv", "asf", "mpeg", "mpg", "vob", "3gp", "3g2", "divx", "xvid",
    ]
    public static let vlcVideo: [String] = [
        "h264", "hevc", "av1", "vp9", "vp8", "mpeg2video", "mpeg4", "msmpeg4v3", "msmpeg4v2", "vc1", "wmv3", "mpeg1video", "h263", "theora", "prores", "mjpeg",
    ]
    public static let vlcAudio: [String] = [
        "aac", "ac3", "eac3", "dts", "dca", "truehd", "mlp", "flac", "alac", "mp3", "mp2", "opus", "vorbis",
        "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le", "pcm_s16be", "pcm_s24be", "pcm_bluray", "pcm_dvd",
        "wmav2", "wmapro", "wmalossless", "ape", "wavpack",
    ]

    public static let textSubtitles: Set<String> = ["srt", "subrip", "ass", "ssa", "vtt", "webvtt", "mov_text", "tx3g", "text", "microdvd", "smi"]
    public static let bitmapSubtitles: Set<String> = ["pgssub", "pgs", "hdmv_pgs_subtitle", "dvdsub", "dvd_subtitle", "dvbsub", "dvb_subtitle", "xsub"]

    /// "mov,mp4,m4a,3gp,3g2,mj2" → ["mov","mp4",...]
    public static func split(_ container: String?) -> [String] {
        (container ?? "").lowercased().split(separator: ",").map(String.init)
    }
}
