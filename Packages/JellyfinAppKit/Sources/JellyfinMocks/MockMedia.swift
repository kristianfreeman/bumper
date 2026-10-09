public import Foundation
import JellyfinAPI
public import Synchronization

/// Real media files served by the mock server, so the playback engines can be
/// exercised end to end (decode, sync, subtitles, seeking) without a Jellyfin
/// install. `scripts/make-test-media.sh` generates the files + `manifest.json`.
public struct MockMediaFixture: Codable, Sendable {
    public struct Video: Codable, Sendable { var codec: String; var width: Int; var height: Int; var fps: Double; var range: String; var bitDepth: Int; var interlaced: Bool? }
    public struct Audio: Codable, Sendable { var codec: String; var channels: Int; var title: String; var profile: String? }
    public struct Subtitle: Codable, Sendable { var codec: String; var title: String; var language: String }

    var file: String
    var name: String
    var container: String
    var duration: Double
    var video: Video?
    var audio: [Audio]
    var subtitles: [Subtitle]
}

public enum MockMedia {
    public static let viewId = "view-testmedia"
    /// Item id → the remote subtitles the "server" has downloaded for it.
    static let downloadedSubtitles = Mutex<[String: [String]]>([:])
    /// The user's display preferences (one record is enough for the mock).
    static let preferences = Mutex<Data>(Data())

    /// What the server's subtitle providers "find" (the OpenSubtitles plugin's shape).
    static func remoteSubtitles(itemId: String) -> [RemoteSubtitle] {
        guard itemId.hasPrefix("media-") else { return [] }
        return [
            RemoteSubtitle(id: "os-1001", providerName: "Open Subtitles", name: "Clip.2024.1080p.WEB-DL.H264-BUMPER", format: "srt", frameRate: 23.976, downloadCount: 4200, isHashMatch: true, threeLetterISOLanguageName: "eng"),
            RemoteSubtitle(id: "os-1002", providerName: "Open Subtitles", name: "Clip.2024.720p.HDTV.x264-OTHER", format: "srt", frameRate: 25, downloadCount: 9100, threeLetterISOLanguageName: "eng"),
            RemoteSubtitle(id: "os-1003", providerName: "Open Subtitles", name: "Clip (SDH)", format: "srt", downloadCount: 1300, hearingImpaired: true, threeLetterISOLanguageName: "eng"),
        ]
    }

    /// A downloaded subtitle's file.
    static func subtitleFile() -> Data {
        Data("1\n00:00:00,500 --> 00:00:04,500\nA subtitle the server found.\n\n2\n00:00:05,000 --> 00:00:09,000\nStill in sync.\n".utf8)
    }

    /// A subtitle stream as the server converts it to WebVTT (any of a
    /// clip's tracks, ASS included: its styling gone).
    static func webVTT() -> Data {
        Data("WEBVTT\n\n00:00:00.500 --> 00:00:04.500\nPlain words, no typesetting.\n\n00:00:05.000 --> 00:00:09.000\nStill in sync.\n".utf8)
    }

    /// Tests: the server can't convert subtitles to WebVTT (it answers 500).
    public static let webVTTFails = Mutex(false)
    private static let state = Mutex<(URL?, [MockMediaFixture])>((nil, []))

    /// Media served by another machine (`mock-media-server` on the Mac):
    /// stream requests are redirected there, so a real Apple TV plays the
    /// clips over the real network.
    private static let remoteBase = Mutex<URL?>(nil)

    /// Points the mock at a remote clip server (manifest fetched now).
    public static func configure(remote base: URL) throws {
        let data = try Data(contentsOf: base.appending(path: "manifest.json"))
        let fixtures = try JSONDecoder().decode([MockMediaFixture].self, from: data)
        remoteBase.withLock { $0 = base }
        state.withLock { $0 = (base, fixtures) }
    }

    /// A plain Range-capable file server for `directory` (the Mac side).
    public static func fileServer(directory: URL) -> MockHTTPServer {
        MockHTTPServer(router: { request in
            let name = request.url?.lastPathComponent ?? ""
            guard !name.isEmpty, !name.contains("..") else { return (404, Data(), ["Content-Type": "text/plain"]) }
            // `?offset=N`: the rest of the file from byte N (MockBooks' audio streams).
            if let offset = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) })?.queryItems?.first(where: { $0.name == "offset" })?.value.flatMap(Int.init),
               let data = try? Data(contentsOf: directory.appending(path: name), options: .alwaysMapped) {
                let body = data.count > offset ? data.subdata(in: offset..<data.count) : Data()
                return (200, body, ["Content-Type": "audio/mpeg", "Content-Length": String(body.count)])
            }
            guard let r = serve(directory.appending(path: name), range: request.value(forHTTPHeaderField: "Range")) else {
                return (404, Data(), ["Content-Type": "text/plain"])
            }
            return r
        }, loopbackOnly: false)
    }

    /// Points the mock at a directory containing `manifest.json` + media.
    public static func configure(directory: URL) {
        let manifest = directory.appending(path: "manifest.json")
        let fixtures = (try? Data(contentsOf: manifest)).flatMap { try? JSONDecoder().decode([MockMediaFixture].self, from: $0) } ?? []
        state.withLock { $0 = (directory, fixtures) }
        MockBooks.configure(directory: directory.appending(path: "books"))
    }

    /// Back to "no real media" (tests).
    public static func reset() {
        state.withLock { $0 = (nil, []) }
    }

    public static var isConfigured: Bool { state.withLock { !$0.1.isEmpty } }

    static var view: BaseItem {
        var v = BaseItem(id: viewId, name: "Test Media", kind: .collectionFolder)
        v.collectionType = "movies"
        return v
    }

    static var items: [BaseItem] {
        let fixtures = state.withLock { $0.1 }
        return fixtures.enumerated().map { i, f in item(i, f) }
    }

    static func item(id: String) -> BaseItem? {
        guard id.hasPrefix("media-"), let i = Int(id.dropFirst(6)) else { return nil }
        let fixtures = state.withLock { $0.1 }
        return fixtures.indices.contains(i) ? item(i, fixtures[i]) : nil
    }

    private static func item(_ i: Int, _ f: MockMediaFixture) -> BaseItem {
        var item = BaseItem(id: "media-\(i)", name: f.name, kind: .movie)
        item.runTimeTicks = Int64(f.duration * Double(BaseItem.ticksPerSecond))
        item.overview = "\(f.container.uppercased()) · " + [f.video.map { "\($0.codec) \($0.height)p \($0.range)" }, f.audio.first.map { "\($0.codec) \($0.channels)ch" }].compactMap { $0 }.joined(separator: " · ")
        item.imageTags = ["Primary": "m\(i)", "Thumb": "mt\(i)"]
        item.backdropImageTags = ["mb\(i)"]
        item.productionYear = 2026
        item.parentId = viewId
        let source = mediaSource(i, f)
        item.mediaSources = [source]
        item.mediaStreams = source.mediaStreams
        item.userData = UserItemData()
        item.chapters = chapters(i, duration: f.duration)
        return item
    }

    /// Named chapters at each quarter (0:30, 1:00 and 1:30 of a 2-minute
    /// seek clip), with images — one named the way rippers leave them.
    static func chapters(_ i: Int, duration: Double) -> [Chapter] {
        ["Arrival", "The Harbour at Night", "Chapter 03", "Landfall"].enumerated().map { n, name in
            Chapter(startPositionTicks: Int64(duration * Double(n) / 4 * Double(BaseItem.ticksPerSecond)), name: name, imageTag: "ch\(i)-\(n)")
        }
    }

    static func mediaSource(_ i: Int, _ f: MockMediaFixture) -> MediaSource {
        var streams: [MediaStream] = []
        var index = 0
        if let v = f.video {
            var s = MediaStream(index: index, type: .video, codec: v.codec)
            s.width = v.width
            s.height = v.height
            s.realFrameRate = v.fps
            s.averageFrameRate = v.fps
            s.bitDepth = v.bitDepth
            s.isInterlaced = v.interlaced ?? false
            s.videoRangeType = v.range
            s.videoRange = v.range == "SDR" ? "SDR" : "HDR"
            if v.range == "HDR10" { s.colorTransfer = "smpte2084"; s.colorPrimaries = "bt2020" }
            streams.append(s)
            index += 1
        }
        for (n, a) in f.audio.enumerated() {
            var s = MediaStream(index: index, type: .audio, codec: a.codec)
            s.channels = a.channels
            s.displayTitle = a.title
            s.profile = a.profile
            s.isDefault = n == 0
            s.language = "eng"
            streams.append(s)
            index += 1
        }
        for sub in f.subtitles {
            var s = MediaStream(index: index, type: .subtitle, codec: sub.codec)
            s.displayTitle = sub.title
            s.language = sub.language
            s.isTextSubtitleStream = !["pgssub", "dvdsub"].contains(sub.codec)
            streams.append(s)
            index += 1
        }
        // Subtitles "downloaded" through the server's subtitle search.
        for remote in downloadedSubtitles.withLock({ $0["media-\(i)"] ?? [] }) {
            var s = MediaStream(index: index, type: .subtitle, codec: "subrip")
            s.displayTitle = "English (\(remote))"
            s.language = "eng"
            s.isExternal = true
            s.isTextSubtitleStream = true
            s.deliveryUrl = "/Videos/media-\(i)/media-\(i)/Subtitles/\(index)/0/Stream.srt"
            streams.append(s)
            index += 1
        }
        var source = MediaSource(id: "media-\(i)", container: f.container, mediaStreams: streams)
        source.supportsDirectPlay = true
        source.supportsDirectStream = true
        source.supportsTranscoding = false
        source.runTimeTicks = Int64(f.duration * Double(BaseItem.ticksPerSecond))
        source.defaultAudioStreamIndex = f.video == nil ? 0 : 1
        return source
    }

    static func playbackInfo(itemId: String) -> PlaybackInfoResponse? {
        guard let item = item(id: itemId), let source = item.mediaSources?.first else { return nil }
        let json = try! JSONEncoder.jellyfin.encode(["MediaSources": [source]])
        var response = try! JSONDecoder.jellyfin.decode(PlaybackInfoResponse.self, from: json)
        response.playSessionId = "mock-\(itemId)"
        return response
    }

    /// HTTP Range support. Responses are capped at 4 MB to mimic servers and
    /// proxies that truncate ranges (the engine must cope).
    /// Theme song shipped in TestMedia/ (every series gets it).
    static let themeSongId = "theme-song"

    static func themeSongs(for itemId: String) -> [BaseItem] {
        guard let dir = state.withLock({ $0.0 }), FileManager.default.fileExists(atPath: dir.appending(path: "theme.m4a").path) else { return [] }
        var song = BaseItem(id: themeSongId, name: "Theme", kind: .audio)
        song.mediaType = "Audio"
        return [song]
    }

    static func audio(itemId: String, range: String?) -> (Int, Data, [String: String])? {
        guard itemId == themeSongId, let dir = state.withLock({ $0.0 }) else { return nil }
        return serve(dir.appending(path: "theme.m4a"), range: range)
    }

    static func stream(itemId: String, range: String?) -> (Int, Data, [String: String])? {
        let (dir, fixtures) = state.withLock { $0 }
        guard let dir, itemId.hasPrefix("media-"), let i = Int(itemId.dropFirst(6)), fixtures.indices.contains(i) else { return nil }
        if let remote = remoteBase.withLock({ $0 }) {
            return (302, Data(), ["Location": remote.appending(path: fixtures[i].file).absoluteString])
        }
        return serve(dir.appending(path: fixtures[i].file), range: range)
    }

    /// A catalog item's "file" for downloads: deterministic stand-in bytes
    /// (the item's id repeated), 3 MB, so a download can be checked byte for byte.
    static func download(itemId: String, range: String?) -> (Int, Data, [String: String]) {
        let size = downloadSize
        var start = 0, end = size - 1
        if let range, range.hasPrefix("bytes=") {
            let p = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            if let s = p.first.flatMap({ Int($0) }) { start = s }
            if p.count > 1, let e = Int(p[1]) { end = min(e, size - 1) }
        }
        guard start < size, start <= end else { return (416, Data(), ["Content-Range": "bytes */\(size)"]) }
        let data = Data((start...end).map { downloadByte(itemId, at: $0) })
        var headers = ["Content-Type": "video/mp4", "Accept-Ranges": "bytes", "Content-Length": String(data.count),
                       "Content-Disposition": "attachment; filename=\"\(itemId).mp4\""]
        if range != nil { headers["Content-Range"] = "bytes \(start)-\(end)/\(size)" }
        return (range == nil ? 200 : 206, data, headers)
    }

    public static let downloadSize = 3 * 1024 * 1024 + 123

    /// The stand-in file's byte at an offset (tests compare against it).
    public static func downloadByte(_ itemId: String, at offset: Int) -> UInt8 {
        let id = Array(itemId.utf8)
        return id[offset % id.count] &+ UInt8(truncatingIfNeeded: offset / id.count)
    }

    /// Simulated server time-to-first-byte for media requests (LAN ≈ 10–30 ms:
    /// the server opens the file and seeks). Applied by MockHTTPServer.
    public static let latency = Mutex<Duration>(.zero)

    static func serve(_ url: URL, range: String?) -> (Int, Data, [String: String])? {
        // Memory-mapped and sliced: a 200 MB open-ended range costs no copy.
        guard let file = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        let size = UInt64(file.count)
        // Honour both ends of "bytes=start-end" (AVFoundation probes with
        // bytes=0-1 and rejects oversized answers); open-ended ranges get the
        // whole remainder, as Jellyfin serves them.
        var start: UInt64 = 0
        var end: UInt64 = size - 1
        if let range, range.hasPrefix("bytes=") {
            let parts = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            if let s = parts.first.flatMap({ UInt64($0) }) { start = s }
            if parts.count > 1, let e = UInt64(parts[1]) { end = min(e, size - 1) }
        }
        guard start < size, start <= end else { return (416, Data(), ["Content-Range": "bytes */\(size)"]) }
        let data = file[Int(start)...Int(end)]
        let type = switch url.pathExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "ts": "video/mp2t"
        case "m4a": "audio/mp4"
        default: "video/x-matroska"
        }
        return (range == nil ? 200 : 206, data, [
            "Content-Type": type,
            "Accept-Ranges": "bytes",
            "Content-Length": String(data.count),
            "Content-Range": "bytes \(start)-\(start + UInt64(data.count) - 1)/\(size)",
        ])
    }
}
