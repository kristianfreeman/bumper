public import AppCore
public import Foundation
public import JellyfinAPI
import Instrumentation

/// Routes each item, at play time, from the media info Jellyfin returned:
///
/// - **AVPlayer** only when *all* of these hold: container MP4/M4V/MOV (or
///   the server's HLS), video H.264/HEVC, audio AAC/AC-3/E-AC-3, and no
///   subtitle selected or a WebVTT one. That path is for Picture in Picture,
///   AirPlay and system Dolby Vision.
/// - **VLCKit** for everything else.
/// - **Server transcode** (HLS → AVPlayer) only over the bitrate cap, for
///   pure Dolby Vision outside MP4, or when this Apple TV can't decode the
///   video in real time.
public struct PlaybackPlanner: Sendable {
    public var capabilities: DeviceCapabilities
    public var preference: EnginePreference
    public var maxBitrate: Int?
    /// Can this device software-decode a stream in real time?
    /// (codec, width, height, fps) → Bool. nil = assume yes.
    public var softwareDecodeCheck: (@Sendable (String, Int, Int, Double) -> Bool)?

    public init(capabilities: DeviceCapabilities, preference: EnginePreference, maxBitrate: Int?, softwareDecodeCheck: (@Sendable (String, Int, Int, Double) -> Bool)? = nil) {
        self.capabilities = capabilities
        self.preference = preference
        self.maxBitrate = maxBitrate
        self.softwareDecodeCheck = softwareDecodeCheck
    }

    /// Would VLCKit decode this video on the CPU? (H.264/HEVC — and AV1/VP9
    /// where the SoC has a decoder — use VideoToolbox; interlaced video is
    /// deinterlaced in software.)
    public func needsSoftwareDecode(_ video: MediaStream) -> Bool {
        if video.isInterlaced == true { return true }
        switch (video.codec ?? "").lowercased() {
        case "h264": return false
        case "hevc": return !capabilities.hevc
        case "av1": return !capabilities.av1Hardware
        case "vp9": return !capabilities.vp9Hardware
        default: return true
        }
    }

    /// Software decode this device can't sustain → better the server
    /// transcodes than playback stutters.
    func softwareDecodeTooHeavy(_ source: MediaSource) -> String? {
        guard let check = softwareDecodeCheck, let video = source.videoStream, needsSoftwareDecode(video) else { return nil }
        let w = video.width ?? 1920, h = video.height ?? 1080
        var fps = video.realFrameRate ?? video.averageFrameRate ?? 24
        if video.isInterlaced == true { fps *= 2 }            // deinterlacing emits one frame per field
        let codec = (video.codec ?? "").lowercased()
        return check(codec, w, h, fps) ? nil : "Software \(codec) \(h)p\(Int(fps.rounded())) too heavy for this Apple TV"
    }

    // MARK: Pure decision logic (unit tested)

    /// Why AVPlayer may not play this source with these selections. Empty ⇒
    /// every AVPlayer condition holds.
    public func avPlayerBlockers(source: MediaSource, audioIndex: Int?, subtitleIndex: Int?) -> [String] {
        var blockers: [String] = []
        let containers = Codecs.split(source.container)
        if !containers.contains(where: Codecs.avPlayerContainers.contains) {
            blockers.append("Container \(containers.first ?? "unknown")")
        }
        if let video = source.videoStream {
            let codec = (video.codec ?? "").lowercased()
            if !Codecs.avPlayerVideo(capabilities).contains(codec) { blockers.append("Video \(codec)") }
            // H.264/HEVC that AVPlayer still can't present properly.
            if video.isInterlaced == true { blockers.append("Interlaced video") }
            if (video.bitDepth ?? 8) > 10 { blockers.append("\(video.bitDepth!)-bit video") }
        }
        let audio = source.audioStreams.first { $0.index == audioIndex } ?? source.audioStreams.first { $0.index == source.defaultAudioStreamIndex } ?? source.audioStreams.first
        if let audio, !Codecs.avPlayerAudio.contains((audio.codec ?? "").lowercased()) {
            blockers.append("Audio \(audio.codec ?? "unknown")")
        }
        if let subtitleIndex, let sub = source.subtitleStreams.first(where: { $0.index == subtitleIndex }),
           !Codecs.avPlayerSubtitles.contains((sub.codec ?? "").lowercased()) {
            blockers.append("Subtitles \(sub.codec ?? "?")")
        }
        return blockers
    }

    public struct Decision: Sendable, Equatable {
        public var engine: EngineKind
        public var method: PlayMethod
        public var reasons: [String]
    }

    /// Chooses backend + method for a source the server has evaluated
    /// against our (VLCKit) device profile.
    public func decide(source: MediaSource, audioIndex: Int?, subtitleIndex: Int?) -> Decision {
        let blockers = avPlayerBlockers(source: source, audioIndex: audioIndex, subtitleIndex: subtitleIndex)
        if source.supportsDirectPlay == false {
            // Over the bitrate cap, or a stream VLCKit can't show (pure DV):
            // the server's HLS, which is AVPlayer's.
            return Decision(engine: .native, method: .transcode, reasons: ["Server transcode (bitrate cap or Dolby Vision outside MP4)"])
        }
        if preference == .automatic && blockers.isEmpty {
            return Decision(engine: .native, method: .directPlay, reasons: ["AVPlayer: MP4/MOV · H.264/HEVC · AAC/AC-3/E-AC-3"])
        }
        if let tooHeavy = softwareDecodeTooHeavy(source), source.supportsTranscoding != false {
            return Decision(engine: .native, method: .transcode, reasons: [tooHeavy])
        }
        return Decision(engine: .vlc, method: .directPlay, reasons: preference == .vlc ? ["VLCKit (forced)"] : blockers)
    }

    /// Always what VLCKit can Direct Play, so the server never transcodes a
    /// file one of our backends can play.
    /// A downloaded file: the same player, the same engine rules — only the
    /// URL is local, and there's no server to transcode, so whatever AVPlayer
    /// can't open goes to VLCKit.
    public func localPlan(item: BaseItem, source: MediaSource, file: URL, startPosition: Duration?, audioIndex: Int?, subtitleIndex: Int?) -> PlaybackPlan {
        let subtitle = subtitleIndex ?? source.defaultSubtitleStreamIndex          // as streaming does
        let blockers = avPlayerBlockers(source: source, audioIndex: audioIndex, subtitleIndex: subtitle)
        let native = preference == .automatic && blockers.isEmpty
        return PlaybackPlan(item: item, mediaSource: source, url: file, engine: native ? .native : .vlc, method: .directPlay,
                            playSessionId: nil, startPosition: startPosition ?? .zero, audioStreamIndex: audioIndex ?? source.defaultAudioStreamIndex,
                            subtitleStreamIndex: subtitle, reasons: ["Downloaded"] + (native ? [] : blockers))
    }

    public func deviceProfile() -> DeviceProfile {
        DeviceProfileBuilder(capabilities: capabilities, maxBitrate: maxBitrate).vlcProfile()
    }

    // MARK: Server round trip

    public enum PlanError: Error, LocalizedError {
        case noMediaSource
        case server(String)
        public var errorDescription: String? {
            switch self {
            case .noMediaSource: "This item has no playable media."
            case .server(let code): "The server can't play this item (\(code))."
            }
        }
    }

    public func plan(
        item: BaseItem,
        client: JellyfinClient,
        startPosition: Duration?,
        mediaSourceId: String? = nil,
        audioIndex: Int? = nil,
        subtitleIndex: Int? = nil
    ) async throws -> PlaybackPlan {
        var request = PlaybackInfoRequest(userId: client.userId, deviceProfile: deviceProfile())
        request.maxStreamingBitrate = maxBitrate
        request.mediaSourceId = mediaSourceId
        request.audioStreamIndex = audioIndex
        request.subtitleStreamIndex = subtitleIndex
        request.startTimeTicks = startPosition?.ticks

        var info = try await Perf.measure("playback.info", .playbackInfo) {
            try await client.playbackInfo(itemId: item.id, request: request)
        }
        if let code = info.errorCode { throw PlanError.server(code) }
        guard var source = info.mediaSources.first(where: { $0.id == mediaSourceId }) ?? info.mediaSources.first else {
            throw PlanError.noMediaSource
        }

        let audio = audioIndex ?? source.defaultAudioStreamIndex
        let subtitle = subtitleIndex ?? source.defaultSubtitleStreamIndex
        var decision = decide(source: source, audioIndex: audio, subtitleIndex: subtitle)

        // We picked "transcode" but asked with the VLCKit profile, so the
        // server may not have produced a URL. Ask again with AVPlayer's profile.
        if decision.method == .transcode && source.transcodingUrl == nil {
            var nativeRequest = request
            nativeRequest.deviceProfile = DeviceProfileBuilder(capabilities: capabilities, maxBitrate: maxBitrate).nativeProfile()
            nativeRequest.enableDirectPlay = false
            nativeRequest.mediaSourceId = source.id
            info = try await client.playbackInfo(itemId: item.id, request: nativeRequest)
            if let refreshed = info.mediaSources.first(where: { $0.id == source.id }) ?? info.mediaSources.first {
                source = refreshed
            }
            guard source.transcodingUrl != nil else { throw PlanError.server("NoCompatibleStream") }
            decision.reasons.append("Re-requested with AVPlayer profile")
        }

        let url: URL
        switch decision.method {
        case .directPlay, .directStream:
            url = client.directStreamURL(itemId: item.id, mediaSourceId: source.id, container: source.container, playSessionId: info.playSessionId)
        case .transcode:
            guard let path = source.transcodingUrl, let abs = client.absoluteURL(serverRelative: path) else { throw PlanError.noMediaSource }
            url = abs
            if path.localizedCaseInsensitiveContains("videocodec=copy") || path.localizedCaseInsensitiveContains("copy") {
                decision.reasons.append("Server remux (no re-encode)")
            }
        }

        return PlaybackPlan(
            item: item,
            mediaSource: source,
            url: url,
            engine: decision.engine,
            method: decision.method,
            playSessionId: info.playSessionId,
            startPosition: startPosition ?? .zero,
            audioStreamIndex: audio,
            subtitleStreamIndex: subtitle,
            reasons: decision.reasons
        )
    }
}
