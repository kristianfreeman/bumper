import AppCore
import Foundation
import JellyfinAPI
@testable import PlaybackCore
import Testing

/// Routing: AVPlayer only when every rule holds; VLCKit otherwise; the
/// server's HLS (→ AVPlayer) only when it must.
@Suite("Playback routing")
struct PlannerTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var container = "mov,mp4,m4a,3gp,3g2,mj2"
        var video = "hevc"
        var audio = "eac3"
        var subtitle: String?            // selected subtitle codec
        var interlaced = false
        var direct = true                // server allows direct play
        var preference = EnginePreference.automatic
        var expect: EngineKind
        var method = PlayMethod.directPlay
        var testDescription: String { "\(container.prefix(4)) \(video)/\(audio)\(subtitle.map { " +\($0)" } ?? "")\(interlaced ? " i" : "")\(direct ? "" : " (no direct)") → \(expect)" }
    }

    static let cases: [Case] = [
        Case(expect: .native),                                              // MP4 HEVC E-AC-3
        Case(video: "h264", audio: "aac", expect: .native),
        Case(audio: "ac3", subtitle: "webvtt", expect: .native),            // WebVTT keeps AVPlayer
        Case(container: "mkv", expect: .vlc),
        Case(container: "mpegts", video: "mpeg2video", audio: "ac3", expect: .vlc),
        Case(audio: "dts", expect: .vlc),
        Case(audio: "truehd", expect: .vlc),
        Case(video: "av1", expect: .vlc),
        Case(subtitle: "subrip", expect: .native),                          // text: WebVTT from the server
        Case(subtitle: "mov_text", expect: .native),
        Case(subtitle: "ass", expect: .vlc),
        Case(subtitle: "pgssub", expect: .vlc),
        Case(interlaced: true, expect: .vlc),
        Case(preference: .vlc, expect: .vlc),
        Case(container: "mkv", direct: false, expect: .native, method: .transcode),   // bitrate cap / pure DV
    ]

    @Test(arguments: cases)
    func routesPerRules(_ c: Case) {
        var v = MediaStream(index: 0, type: .video, codec: c.video)
        v.isInterlaced = c.interlaced
        v.bitDepth = 10
        var streams = [v, MediaStream(index: 1, type: .audio, codec: c.audio)]
        if let sub = c.subtitle { streams.append(MediaStream(index: 2, type: .subtitle, codec: sub)) }
        var src = MediaSource(id: "m", container: c.container, mediaStreams: streams)
        src.supportsDirectPlay = c.direct
        src.transcodingUrl = c.direct ? nil : "/videos/m/master.m3u8"
        let planner = PlaybackPlanner(capabilities: .appleTV4KReference, preference: c.preference, maxBitrate: nil)
        let d = planner.decide(source: src, audioIndex: nil, subtitleIndex: c.subtitle == nil ? nil : 2)
        #expect(d.engine == c.expect && d.method == c.method, "\(d.reasons)")
    }

    /// The *selected* tracks decide, not merely their presence in the file.
    @Test func selectedTracksDecide() {
        var src = MediaSource(id: "m", container: "mp4", mediaStreams: [
            MediaStream(index: 0, type: .video, codec: "h264"), MediaStream(index: 1, type: .audio, codec: "aac"),
            MediaStream(index: 2, type: .audio, codec: "truehd"), MediaStream(index: 3, type: .subtitle, codec: "pgssub"),
        ])
        src.supportsDirectPlay = true
        let p = PlaybackPlanner(capabilities: .appleTV4KReference, preference: .automatic, maxBitrate: nil)
        #expect(p.decide(source: src, audioIndex: 1, subtitleIndex: nil).engine == .native)
        #expect(p.decide(source: src, audioIndex: 2, subtitleIndex: nil).engine == .vlc)
        #expect(p.decide(source: src, audioIndex: 1, subtitleIndex: 3).engine == .vlc)
    }
}

@Suite("Device profile")
struct DeviceProfileTests {
    /// We declare what VLCKit Direct Plays — except pure Dolby Vision, which
    /// the server repackages for AVPlayer.
    @Test func declaresVLCKitDirectPlay() throws {
        let profile = DeviceProfileBuilder(capabilities: .appleTV4KReference, maxBitrate: nil).vlcProfile()
        let video = try #require(profile.directPlayProfiles.first { $0.type == "Video" })
        for c in ["mkv", "avi", "ts", "m2ts"] { #expect(video.container.contains(c)) }
        for a in ["dts", "truehd", "eac3", "flac", "opus"] { #expect(video.audioCodec?.contains(a) == true) }
        for v in ["hevc", "av1", "vc1", "mpeg2video"] { #expect(video.videoCodec?.contains(v) == true) }
        #expect(profile.subtitleProfiles.contains { $0.format == "pgssub" && $0.method == "Embed" })
        let hevc = try #require(profile.codecProfiles.first { $0.codec == "hevc" })
        let ranges = try #require(hevc.conditions.first { $0.property == "VideoRangeType" }).value.split(separator: "|").map(String.init)
        #expect(ranges.contains("DOVIWithHDR10") && !ranges.contains("DOVI"))
    }

    @Test func transcodesToFMP4HLSWithHEVCFirst() throws {
        let t = try #require(DeviceProfileBuilder(capabilities: .appleTV4KReference, maxBitrate: nil).nativeProfile().transcodingProfiles.first)
        #expect(t.container == "mp4" && t.protocol == "hls")
        #expect(t.videoCodec.hasPrefix("hevc"))
        #expect(t.audioCodec.hasPrefix("eac3"))
        let json = String(decoding: try JSONEncoder().encode(DeviceProfileBuilder(capabilities: .appleTV4KReference, maxBitrate: 20_000_000).vlcProfile()), as: UTF8.self)
        #expect(json.contains("\"DirectPlayProfiles\"") && json.contains("\"MaxStreamingBitrate\":20000000"))
    }
}

@Suite("Subtitles")
struct SubtitleTests {
    @Test func parsesSRTWithTags() {
        let srt = "1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i>\r\nthere\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nBye\r\n"
        let track = SubtitleParser.parse(Data(srt.utf8), format: "srt")
        #expect(track.cues.count == 2)
        #expect(track.text(at: .milliseconds(1500)) == "Hello\nthere")
        #expect(track.text(at: .milliseconds(2700)) == nil)
    }

    @Test func parsesWebVTTWithCueSettings() {
        let vtt = "WEBVTT\n\n00:01.000 --> 00:02.000 align:start position:10%\nShort timestamps\n"
        #expect(SubtitleParser.parse(Data(vtt.utf8), format: "vtt").text(at: .milliseconds(1200)) == "Short timestamps")
    }

    @Test func parsesASSAndStripsOverrides() {
        let ass = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:05.00,0:00:07.50,Default,,0,0,0,,{\\an8\\i1}Top line\\Nsecond, with comma
        """
        let track = SubtitleParser.parse(Data(ass.utf8), format: "ass")
        #expect(track.text(at: .seconds(6)) == "Top line\nsecond, with comma")
    }

    @Test func overlappingCuesAreJoined() {
        let track = SubtitleTrack(cues: [
            TimedCue(start: .seconds(0), end: .seconds(10), text: "A"),
            TimedCue(start: .seconds(2), end: .seconds(3), text: "B"),
        ])
        #expect(track.text(at: .milliseconds(2500)) == "A\nB")
    }

    @Test(.enabled(if: isOptimized, "timing budget: optimized builds only")) func lookupIsFastOnLargeTracks() {
        let cues = (0..<20_000).map { TimedCue(start: .seconds($0 * 3), end: .seconds($0 * 3 + 2), text: "line \($0)") }
        let track = SubtitleTrack(cues: cues)
        let elapsed = ContinuousClock().measure {
            for i in 0..<10_000 { _ = track.text(at: .seconds(i * 6 + 1)) }
        }
        #expect(elapsed < .milliseconds(100), "10k lookups took \(elapsed)")
    }
}

/// Timing budgets are only meaningful in optimized builds; debug runs skip
/// them (`scripts/test.sh perf` runs them with -c release).
let isOptimized: Bool = {
    #if DEBUG
    false
    #else
    true
    #endif
}()

@Suite("Default subtitle selection")
struct SubtitleSelectionTests {
    func sub(_ index: Int, _ lang: String?, forced: Bool = false, title: String? = nil) -> MediaStream {
        var s = MediaStream(index: index, type: .subtitle, codec: "subrip")
        s.language = lang
        s.isForced = forced
        s.title = title
        return s
    }

    @Test func honoursServerDefaultFirst() {
        let streams = [sub(2, "eng"), sub(3, "spa")]
        #expect(SubtitleSelection.choose(from: streams, serverDefault: 3, preferredLanguages: ["en"]) == 3)
    }

    @Test func picksPreferredLanguageSkippingForcedAndSDH() {
        let streams = [sub(2, "eng", forced: true), sub(3, "eng", title: "English SDH"), sub(4, "eng", title: "English"), sub(5, "fre")]
        #expect(SubtitleSelection.choose(from: streams, serverDefault: nil, preferredLanguages: ["en-US"]) == 4)
    }

    @Test func fallsBackToFirstFullTrack() {
        let streams = [sub(2, "jpn", forced: true), sub(3, "ger")]
        #expect(SubtitleSelection.choose(from: streams, serverDefault: nil, preferredLanguages: ["en"]) == 3)
    }

    @Test func noSubtitlesMeansNone() {
        #expect(SubtitleSelection.choose(from: [MediaStream(index: 0, type: .video, codec: "h264")], serverDefault: nil, preferredLanguages: ["en"]) == nil)
    }
}

@Suite("Software decode budget")
struct SoftwareDecodeBudgetTests {
    func source(_ codec: String, _ w: Int, _ h: Int, fps: Double = 24, interlaced: Bool = false) -> MediaSource {
        var v = MediaStream(index: 0, type: .video, codec: codec)
        v.width = w; v.height = h; v.realFrameRate = fps; v.isInterlaced = interlaced
        var src = MediaSource(id: "m", container: "mkv", mediaStreams: [v, MediaStream(index: 1, type: .audio, codec: "aac")])
        src.supportsDirectPlay = true
        src.supportsTranscoding = true
        return src
    }

    func decide(_ model: String, _ src: MediaSource) -> PlaybackPlanner.Decision {
        let budget = SoftwareDecodeBudget.forModel(model)
        return PlaybackPlanner(capabilities: .appleTV4KReference, preference: .automatic, maxBitrate: nil,
                               softwareDecodeCheck: { codec, w, h, fps in budget.allows(codec: codec, pixelRate: Double(w * h) * fps) })
            .decide(source: src, audioIndex: nil, subtitleIndex: nil)
    }

    /// The A10X can't software-decode 4K AV1 (→ server HLS); hardware codecs
    /// and newer models are never limited; interlaced counts its field rate.
    @Test func limitsOnlyWhatTheChipCantDecode() {
        #expect(decide("AppleTV6,2", source("av1", 3840, 2160)).method == .transcode)
        #expect(decide("AppleTV6,2", source("av1", 1920, 1080)).engine == .vlc)
        #expect(decide("AppleTV6,2", source("hevc", 3840, 2160)).engine == .vlc)
        #expect(decide("AppleTV14,1", source("av1", 3840, 2160)).engine == .vlc)
        #expect(decide("AppleTV6,2", source("mpeg2video", 1920, 1080, fps: 29.97, interlaced: true)).engine == .vlc)
        #expect(decide("AppleTV6,2", source("vc1", 1920, 1080, fps: 29.97, interlaced: true)).method == .transcode)
    }
}

/// A downloaded file plays like a stream: AVPlayer when it can, VLCKit
/// otherwise — never a server transcode (there's no server).
@Suite("Downloaded playback")
struct LocalPlanTests {
    @Test func picksTheEngineLikeStreaming() {
        let planner = PlaybackPlanner(capabilities: .appleTV4KReference, preference: .automatic, maxBitrate: nil)
        let item = BaseItem(id: "f", name: "F", kind: .movie)
        let file = URL(fileURLWithPath: "/tmp/f/media.mp4")
        let mp4 = MediaSource(id: "s", container: "mp4", mediaStreams: [MediaStream(index: 0, type: .video, codec: "h264"), MediaStream(index: 1, type: .audio, codec: "aac")])
        let mkv = MediaSource(id: "s", container: "mkv", mediaStreams: [MediaStream(index: 0, type: .video, codec: "h264"), MediaStream(index: 1, type: .audio, codec: "dts")])
        let a = planner.localPlan(item: item, source: mp4, file: file, startPosition: nil, audioIndex: nil, subtitleIndex: nil)
        #expect(a.engine == .native && a.method == .directPlay && a.url == file)
        let b = planner.localPlan(item: item, source: mkv, file: file, startPosition: .seconds(30), audioIndex: nil, subtitleIndex: nil)
        #expect(b.engine == .vlc && b.method == .directPlay && b.startPosition == .seconds(30))
    }
}

@Test func aResumePointPastTheEndStartsFromTheBeginning() {
    #expect(PlaybackPlanner.usableStart(.seconds(4387), runtime: .seconds(1200)) == nil)
    #expect(PlaybackPlanner.usableStart(.seconds(1198), runtime: .seconds(1200)) == nil)
    #expect(PlaybackPlanner.usableStart(.seconds(600), runtime: .seconds(1200)) == .seconds(600))
    #expect(PlaybackPlanner.usableStart(.seconds(600), runtime: nil) == .seconds(600))
}
