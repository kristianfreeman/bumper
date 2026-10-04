import Foundation

public struct MediaSource: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String?
    public var path: String?
    public var container: String?
    public var size: Int64?
    public var bitrate: Int?
    public var runTimeTicks: Int64?
    public var protocolType: String?
    public var isRemote: Bool?
    public var supportsDirectPlay: Bool?
    public var supportsDirectStream: Bool?
    public var supportsTranscoding: Bool?
    public var transcodingUrl: String?
    public var transcodingSubProtocol: String?
    public var transcodingContainer: String?
    public var directStreamUrl: String?
    public var eTag: String?
    public var mediaStreams: [MediaStream]?
    public var defaultAudioStreamIndex: Int?
    public var defaultSubtitleStreamIndex: Int?
    public var videoType: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", path = "Path", container = "Container", size = "Size", bitrate = "Bitrate"
        case runTimeTicks = "RunTimeTicks", protocolType = "Protocol", isRemote = "IsRemote"
        case supportsDirectPlay = "SupportsDirectPlay", supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding", transcodingUrl = "TranscodingUrl"
        case transcodingSubProtocol = "TranscodingSubProtocol", transcodingContainer = "TranscodingContainer"
        case directStreamUrl = "DirectStreamUrl", eTag = "ETag", mediaStreams = "MediaStreams"
        case defaultAudioStreamIndex = "DefaultAudioStreamIndex", defaultSubtitleStreamIndex = "DefaultSubtitleStreamIndex"
        case videoType = "VideoType"
    }

    public init(id: String, container: String?, mediaStreams: [MediaStream]) {
        self.id = id
        self.container = container
        self.mediaStreams = mediaStreams
    }

    public var videoStream: MediaStream? { mediaStreams?.first { $0.type == .video } }
    public var audioStreams: [MediaStream] { mediaStreams?.filter { $0.type == .audio } ?? [] }
    public var subtitleStreams: [MediaStream] { mediaStreams?.filter { $0.type == .subtitle } ?? [] }
}

public enum MediaStreamType: String, Codable, Sendable, Hashable {
    case video = "Video", audio = "Audio", subtitle = "Subtitle", embeddedImage = "EmbeddedImage", data = "Data", lyric = "Lyric"
    case unknown

    public init(from decoder: any Decoder) throws {
        self = MediaStreamType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct MediaStream: Codable, Sendable, Hashable {
    public var index: Int
    public var type: MediaStreamType
    public var codec: String?
    public var codecTag: String?
    public var profile: String?
    public var level: Double?
    public var language: String?
    public var title: String?
    public var displayTitle: String?
    public var isDefault: Bool?
    public var isForced: Bool?
    public var isExternal: Bool?
    public var isTextSubtitleStream: Bool?
    public var deliveryUrl: String?
    public var deliveryMethod: String?
    public var bitRate: Int?
    public var bitDepth: Int?
    public var width: Int?
    public var height: Int?
    public var averageFrameRate: Double?
    public var realFrameRate: Double?
    public var isInterlaced: Bool?
    public var pixelFormat: String?
    public var channels: Int?
    public var channelLayout: String?
    public var sampleRate: Int?
    public var videoRange: String?          // "SDR", "HDR"
    public var videoRangeType: String?      // "SDR", "HDR10", "HDR10Plus", "HLG", "DOVI", "DOVIWithHDR10", ...
    public var colorTransfer: String?
    public var colorPrimaries: String?
    public var colorSpace: String?
    public var dvVersionMajor: Int?
    public var dvVersionMinor: Int?
    public var dvProfile: Int?
    public var dvLevel: Int?
    public var rpuPresentFlag: Int?
    public var elPresentFlag: Int?
    public var blPresentFlag: Int?
    public var dvBlSignalCompatibilityId: Int?
    public var audioSpatialFormat: String?  // 10.11: "None", "DolbyAtmos", "DTSX"

    enum CodingKeys: String, CodingKey {
        case index = "Index", type = "Type", codec = "Codec", codecTag = "CodecTag", profile = "Profile", level = "Level"
        case language = "Language", title = "Title", displayTitle = "DisplayTitle", isDefault = "IsDefault"
        case isForced = "IsForced", isExternal = "IsExternal", isTextSubtitleStream = "IsTextSubtitleStream"
        case deliveryUrl = "DeliveryUrl", deliveryMethod = "DeliveryMethod", bitRate = "BitRate", bitDepth = "BitDepth"
        case width = "Width", height = "Height", averageFrameRate = "AverageFrameRate", realFrameRate = "RealFrameRate"
        case isInterlaced = "IsInterlaced", pixelFormat = "PixelFormat", channels = "Channels"
        case channelLayout = "ChannelLayout", sampleRate = "SampleRate", videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType", colorTransfer = "ColorTransfer", colorPrimaries = "ColorPrimaries"
        case colorSpace = "ColorSpace", dvVersionMajor = "DvVersionMajor", dvVersionMinor = "DvVersionMinor"
        case dvProfile = "DvProfile", dvLevel = "DvLevel", rpuPresentFlag = "RpuPresentFlag"
        case elPresentFlag = "ElPresentFlag", blPresentFlag = "BlPresentFlag"
        case dvBlSignalCompatibilityId = "DvBlSignalCompatibilityId", audioSpatialFormat = "AudioSpatialFormat"
    }

    public init(index: Int, type: MediaStreamType, codec: String?) {
        self.index = index
        self.type = type
        self.codec = codec
    }

    public var isDolbyVision: Bool { (videoRangeType ?? "").hasPrefix("DOVI") || dvProfile != nil }
    public var isAtmos: Bool {
        audioSpatialFormat == "DolbyAtmos" || (profile ?? "").localizedCaseInsensitiveContains("atmos")
            || (displayTitle ?? "").localizedCaseInsensitiveContains("atmos")
    }
}

// MARK: - Playback info

public struct PlaybackInfoRequest: Encodable, Sendable {
    public var userId: String?
    public var maxStreamingBitrate: Int?
    public var startTimeTicks: Int64?
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?
    public var mediaSourceId: String?
    public var deviceProfile: DeviceProfile?
    public var enableDirectPlay: Bool = true
    public var enableDirectStream: Bool = true
    public var enableTranscoding: Bool = true
    public var allowVideoStreamCopy: Bool = true
    public var allowAudioStreamCopy: Bool = true
    public var autoOpenLiveStream: Bool = true
    public var alwaysBurnInSubtitleWhenTranscoding: Bool = false

    enum CodingKeys: String, CodingKey {
        case userId = "UserId", maxStreamingBitrate = "MaxStreamingBitrate", startTimeTicks = "StartTimeTicks"
        case audioStreamIndex = "AudioStreamIndex", subtitleStreamIndex = "SubtitleStreamIndex"
        case mediaSourceId = "MediaSourceId", deviceProfile = "DeviceProfile", enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream", enableTranscoding = "EnableTranscoding"
        case allowVideoStreamCopy = "AllowVideoStreamCopy", allowAudioStreamCopy = "AllowAudioStreamCopy"
        case autoOpenLiveStream = "AutoOpenLiveStream"
        case alwaysBurnInSubtitleWhenTranscoding = "AlwaysBurnInSubtitleWhenTranscoding"
    }

    public init(userId: String?, deviceProfile: DeviceProfile?) {
        self.userId = userId
        self.deviceProfile = deviceProfile
    }
}

public struct PlaybackInfoResponse: Codable, Sendable {
    public var mediaSources: [MediaSource]
    public var playSessionId: String?
    public var errorCode: String?

    enum CodingKeys: String, CodingKey { case mediaSources = "MediaSources", playSessionId = "PlaySessionId", errorCode = "ErrorCode" }
}

// MARK: - Device profile (what we tell the server we can play)

public struct DeviceProfile: Codable, Sendable, Hashable {
    public var name: String
    public var maxStreamingBitrate: Int?
    public var maxStaticBitrate: Int?
    public var musicStreamingTranscodingBitrate: Int?
    public var directPlayProfiles: [DirectPlayProfile]
    public var transcodingProfiles: [TranscodingProfile]
    public var codecProfiles: [CodecProfile]
    public var subtitleProfiles: [SubtitleProfile]
    public var containerProfiles: [ContainerProfile] = []

    enum CodingKeys: String, CodingKey {
        case name = "Name", maxStreamingBitrate = "MaxStreamingBitrate", maxStaticBitrate = "MaxStaticBitrate"
        case musicStreamingTranscodingBitrate = "MusicStreamingTranscodingBitrate"
        case directPlayProfiles = "DirectPlayProfiles", transcodingProfiles = "TranscodingProfiles"
        case codecProfiles = "CodecProfiles", subtitleProfiles = "SubtitleProfiles", containerProfiles = "ContainerProfiles"
    }

    public init(name: String, maxStreamingBitrate: Int?, directPlayProfiles: [DirectPlayProfile], transcodingProfiles: [TranscodingProfile], codecProfiles: [CodecProfile], subtitleProfiles: [SubtitleProfile]) {
        self.name = name
        self.maxStreamingBitrate = maxStreamingBitrate
        self.maxStaticBitrate = maxStreamingBitrate
        self.directPlayProfiles = directPlayProfiles
        self.transcodingProfiles = transcodingProfiles
        self.codecProfiles = codecProfiles
        self.subtitleProfiles = subtitleProfiles
    }
}

public struct DirectPlayProfile: Codable, Sendable, Hashable {
    public var container: String
    public var audioCodec: String?
    public var videoCodec: String?
    public var type: String

    enum CodingKeys: String, CodingKey { case container = "Container", audioCodec = "AudioCodec", videoCodec = "VideoCodec", type = "Type" }

    public init(container: [String], audio: [String]?, video: [String]?, type: String = "Video") {
        self.container = container.joined(separator: ",")
        self.audioCodec = audio?.joined(separator: ",")
        self.videoCodec = video?.joined(separator: ",")
        self.type = type
    }
}

public struct TranscodingProfile: Codable, Sendable, Hashable {
    public var container: String
    public var type: String
    public var videoCodec: String
    public var audioCodec: String
    public var `protocol`: String
    public var context: String = "Streaming"
    public var maxAudioChannels: String?
    public var minSegments: Int?
    public var breakOnNonKeyFrames: Bool?
    public var enableSubtitlesInManifest: Bool?
    public var copyTimestamps: Bool?

    enum CodingKeys: String, CodingKey {
        case container = "Container", type = "Type", videoCodec = "VideoCodec", audioCodec = "AudioCodec"
        case `protocol` = "Protocol", context = "Context", maxAudioChannels = "MaxAudioChannels"
        case minSegments = "MinSegments", breakOnNonKeyFrames = "BreakOnNonKeyFrames"
        case enableSubtitlesInManifest = "EnableSubtitlesInManifest", copyTimestamps = "CopyTimestamps"
    }

    public init(container: String, type: String = "Video", video: [String], audio: [String], protocol: String, maxAudioChannels: Int?) {
        self.container = container
        self.type = type
        self.videoCodec = video.joined(separator: ",")
        self.audioCodec = audio.joined(separator: ",")
        self.protocol = `protocol`
        self.maxAudioChannels = maxAudioChannels.map(String.init)
        self.minSegments = 2
        self.breakOnNonKeyFrames = true
        self.enableSubtitlesInManifest = true
    }
}

public struct ProfileCondition: Codable, Sendable, Hashable {
    public var condition: String   // Equals, NotEquals, LessThanEqual, GreaterThanEqual, EqualsAny
    public var property: String    // VideoRangeType, VideoBitDepth, Width, VideoLevel, VideoProfile, AudioChannels...
    public var value: String
    public var isRequired: Bool

    enum CodingKeys: String, CodingKey { case condition = "Condition", property = "Property", value = "Value", isRequired = "IsRequired" }

    public init(_ condition: String, _ property: String, _ value: String, required: Bool = false) {
        self.condition = condition
        self.property = property
        self.value = value
        self.isRequired = required
    }
}

public struct CodecProfile: Codable, Sendable, Hashable {
    public var type: String          // Video, VideoAudio, Audio
    public var codec: String?
    public var container: String?
    public var conditions: [ProfileCondition]
    public var applyConditions: [ProfileCondition]

    enum CodingKeys: String, CodingKey { case type = "Type", codec = "Codec", container = "Container", conditions = "Conditions", applyConditions = "ApplyConditions" }

    public init(type: String, codec: String?, conditions: [ProfileCondition], applyConditions: [ProfileCondition] = []) {
        self.type = type
        self.codec = codec
        self.conditions = conditions
        self.applyConditions = applyConditions
    }
}

public struct SubtitleProfile: Codable, Sendable, Hashable {
    public var format: String
    public var method: String        // Embed, External, Hls, Encode

    enum CodingKeys: String, CodingKey { case format = "Format", method = "Method" }

    public init(_ format: String, _ method: String) {
        self.format = format
        self.method = method
    }
}

public struct ContainerProfile: Codable, Sendable, Hashable {
    public var type: String
    public var container: String
    public var conditions: [ProfileCondition]
    enum CodingKeys: String, CodingKey { case type = "Type", container = "Container", conditions = "Conditions" }
}

// MARK: - Media segments (10.10+: intros, outros, recaps, previews, commercials)

public struct MediaSegment: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case unknown = "Unknown", commercial = "Commercial", preview = "Preview", recap = "Recap", outro = "Outro", intro = "Intro"
        /// An unrecognised type must not fail the whole list (it did: one
        /// odd segment and Skip Intro silently never appeared).
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? Kind.allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame } ?? .unknown
        }
    }

    public var id: String
    public var itemId: String
    public var type: Kind
    public var startTicks: Int64
    public var endTicks: Int64

    enum CodingKeys: String, CodingKey { case id = "Id", itemId = "ItemId", type = "Type", startTicks = "StartTicks", endTicks = "EndTicks" }

    public init(id: String, itemId: String, type: Kind, startTicks: Int64, endTicks: Int64) {
        self.id = id
        self.itemId = itemId
        self.type = type
        self.startTicks = startTicks
        self.endTicks = endTicks
    }

    public var range: Range<Duration> { .ticks(startTicks) ..< .ticks(max(endTicks, startTicks)) }

    /// Segments from chapter names ("Intro", "Opening", "Credits", "Recap"…)
    /// for libraries without a segment provider — common for anime and
    /// Blu-ray rips. A chapter ends where the next begins.
    public static func fromChapters(_ chapters: [Chapter], itemId: String, runtimeTicks: Int64?) -> [MediaSegment] {
        let sorted = chapters.sorted { $0.startPositionTicks < $1.startPositionTicks }
        return sorted.enumerated().compactMap { i, chapter in
            guard let kind = kind(forChapter: chapter.name ?? "") else { return nil }
            guard let end = i + 1 < sorted.count ? sorted[i + 1].startPositionTicks : runtimeTicks, end > chapter.startPositionTicks else { return nil }
            return MediaSegment(id: "chapter-\(i)", itemId: itemId, type: kind, startTicks: chapter.startPositionTicks, endTicks: end)
        }
    }

    static func kind(forChapter name: String) -> Kind? {
        let n = name.lowercased().trimmingCharacters(in: .whitespaces)
        func any(_ words: [String]) -> Bool { words.contains { n == $0 || n.hasPrefix($0 + " ") || n.contains(" " + $0) } }
        if any(["intro", "introduction", "opening", "op", "opening credits", "title sequence", "theme song"]) { return .intro }
        if any(["recap", "previously", "previously on"]) { return .recap }
        if any(["credits", "end credits", "ending", "ed", "outro", "closing credits"]) { return .outro }
        if any(["preview", "next episode", "next time"]) { return .preview }
        return nil
    }
}

extension MediaSegment.Kind: CaseIterable {}

public struct MediaSegmentsPage: Codable, Sendable {
    public var items: [MediaSegment]
    enum CodingKeys: String, CodingKey { case items = "Items" }
    public init(items: [MediaSegment]) { self.items = items }
}

// MARK: - Session reporting

public struct PlaybackProgressReport: Encodable, Sendable {
    public var itemId: String
    public var mediaSourceId: String?
    public var playSessionId: String?
    public var positionTicks: Int64
    public var isPaused: Bool
    public var isMuted: Bool = false
    public var playMethod: String              // DirectPlay, DirectStream, Transcode
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?
    public var canSeek: Bool = true
    public var failed: Bool = false

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId", mediaSourceId = "MediaSourceId", playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks", isPaused = "IsPaused", isMuted = "IsMuted", playMethod = "PlayMethod"
        case audioStreamIndex = "AudioStreamIndex", subtitleStreamIndex = "SubtitleStreamIndex", canSeek = "CanSeek"
        case failed = "Failed"
    }

    public init(itemId: String, mediaSourceId: String?, playSessionId: String?, positionTicks: Int64, isPaused: Bool, playMethod: String, audioStreamIndex: Int?, subtitleStreamIndex: Int?) {
        self.itemId = itemId
        self.mediaSourceId = mediaSourceId
        self.playSessionId = playSessionId
        self.positionTicks = positionTicks
        self.isPaused = isPaused
        self.playMethod = playMethod
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
    }
}
