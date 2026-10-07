public import Foundation
import CoreGraphics
import ImageIO
public import JellyfinAPI
public import Synchronization
import UniformTypeIdentifiers

/// An in-process Jellyfin 10.11 server, implemented as a URLProtocol.
///
/// Inject via `URLSessionConfiguration.protocolClasses`; every request to
/// `MockJellyfinProtocol.baseURL` is answered from `MockCatalog` with
/// realistic (configurable) latency. Used by UI tests, perf tests, previews,
/// and the `-mock` launch argument.
public final class MockJellyfinProtocol: URLProtocol, @unchecked Sendable {
    public static let host = "mock.jellyfin.local"
    public static let baseURL = URL(string: "http://\(host)")!
    public static let userId = "mock-user"
    public static let token = "mock-token"

    /// Simulated server latency (a fast LAN server is 5–30 ms).
    public static let latency = Mutex<Duration>(.milliseconds(25))
    private static let quickConnectPolls = Atomic<Int>(0)
    private static let imageCache = Mutex<[String: Data]>([:])

    private let cancelled = Atomic<Bool>(false)

    /// Sign-in result for the mock user (lets the app skip onboarding with `-mock`).
    public static var authenticationResult: AuthenticationResult { MockAuth.result }

    public override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        let delay = Self.latency.withLock { $0 }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay.timeInterval) { [self] in
            guard !cancelled.load(ordering: .relaxed) else { return }
            let (status, body, headers) = Self.route(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    public override func stopLoading() {
        cancelled.store(true, ordering: .relaxed)
    }

    // MARK: Routing

    /// Single entry point shared by the URLProtocol and `MockHTTPServer`.
    public static func route(_ request: URLRequest) -> (Int, Data, [String: String]) {
        let parts = request.url!.path.split(separator: "/")
        if parts.count >= 3, parts[0] == "Videos", parts[2].hasPrefix("stream"),
           let media = MockMedia.stream(itemId: String(parts[1]), range: request.value(forHTTPHeaderField: "Range")) {
            return media
        }
        // A transcode of a catalog item (static=false): stand-in bytes, sent
        // as the real server sends a transcode — no length, no ranges.
        if parts.count >= 3, parts[0] == "Videos", parts[2].hasPrefix("stream"),
           request.url?.query?.lowercased().contains("static=false") == true {
            var r = MockMedia.download(itemId: String(parts[1]), range: nil)
            r.2["Content-Length"] = nil
            r.2["Accept-Ranges"] = nil
            return r
        }
        // Downloads: a test clip's own file, or (any other item) stand-in
        // bytes, both with byte ranges like the real server.
        if parts.count == 3, parts[0] == "Items", parts[2] == "Download" {
            let range = request.value(forHTTPHeaderField: "Range")
            return MockMedia.stream(itemId: String(parts[1]), range: range) ?? MockMedia.download(itemId: String(parts[1]), range: range)
        }
        if parts.count >= 3, parts[0] == "Audio", parts[2].hasPrefix("stream") {
            let ticks = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name.lowercased() == "starttimeticks" }?.value
            if let book = MockBooks.stream(itemId: String(parts[1]), startTicks: Int64(ticks ?? "") ?? 0) { return book }
        }
        if parts.count >= 3, parts[0] == "Audio", let audio = MockMedia.audio(itemId: String(parts[1]), range: request.value(forHTTPHeaderField: "Range")) {
            return audio
        }
        let r = respond(to: request)
        return (r.0, r.1, ["Content-Type": r.2])
    }

    static func respond(to request: URLRequest) -> (Int, Data, String) {
        guard let url = request.url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return (400, Data(), "text/plain") }
        let path = comps.path
        let q = Dictionary((comps.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let catalog = MockCatalog.shared
        let parts = path.split(separator: "/").map(String.init)

        func json<T: Encodable>(_ value: T) -> (Int, Data, String) {
            (200, (try? JSONEncoder.jellyfin.encode(value)) ?? Data(), "application/json")
        }
        func page(_ items: [BaseItem]) -> (Int, Data, String) {
            let start = Int(q["startindex"] ?? "") ?? 0
            let limit = Int(q["limit"] ?? "") ?? items.count
            let slice = Array(items.dropFirst(start).prefix(limit))
            return json(ItemsPage(items: slice, totalRecordCount: items.count, startIndex: start))
        }

        switch (request.httpMethod ?? "GET", path) {
        case (_, "/System/Info/Public"):
            return json(PublicSystemInfo(id: "mock-server", serverName: "Mock Jellyfin", version: "10.11.11"))
        case (_, "/Users/Public"):
            var u = UserDto(id: userId, name: "Tester")
            u.hasPassword = false
            return json([u])
        case (_, "/Users/AuthenticateByName"), (_, "/Users/AuthenticateWithQuickConnect"):
            return json(MockAuth.result)
        case (_, "/Users/Me"):
            return json(MockAuth.result.user)
        case (_, "/UserImage"):
            return (200, image(for: "avatar-\(q["userid"] ?? "")", width: Int(q["maxwidth"] ?? "") ?? 200, aspect: 1), "image/jpeg")
        case (_, "/QuickConnect/Enabled"):
            return json(true)
        case (_, "/QuickConnect/Initiate"):
            quickConnectPolls.store(0, ordering: .relaxed)
            return json(MockAuth.quickConnect(authenticated: false))
        case (_, "/QuickConnect/Connect"):
            let polls = quickConnectPolls.add(1, ordering: .relaxed).newValue
            return json(MockAuth.quickConnect(authenticated: polls >= 2))
        case (_, "/UserViews"):
            var views = (MockMedia.isConfigured ? [MockMedia.view] : []) + catalog.views + (MockBooks.isConfigured ? [MockBooks.view] : [])
            // `-mockLibraries "Books:books,Videos:homevideos"`: extra (empty) libraries, to mirror a real server's sidebar.
            for spec in (UserDefaults.standard.string(forKey: "mockLibraries") ?? "").split(separator: ",") {
                let parts = spec.split(separator: ":").map(String.init)
                guard parts.count == 2 else { continue }
                var v = BaseItem(id: "view-extra-\(parts[0].lowercased())", name: parts[0], kind: .collectionFolder)
                v.collectionType = parts[1]
                views.append(v)
            }
            return json(ItemsPage(items: views, totalRecordCount: views.count))
        case (_, "/UserItems/Resume"):
            let inProgress = catalog.movies.filter { $0.progress != nil } + catalog.episodes.values.flatMap { $0 }.filter { $0.progress != nil }
            return page(Array(inProgress.prefix(Int(q["limit"] ?? "") ?? 12)))
        case (_, "/Shows/NextUp"):
            let next = catalog.series.prefix(16).compactMap { s in catalog.seasons[s.id]?.last.flatMap { catalog.episodes[$0.id]?.first { !$0.isPlayed } } }
            return page(next)
        case (_, "/Items/Latest") where q["parentid"] == MockMedia.viewId:
            return json(MockMedia.items)
        case (_, "/Items") where q["parentid"] == MockMedia.viewId:
            return page(MockMedia.items)
        case (_, "/Items") where q["parentid"].flatMap(MockBooks.children(of:)) != nil:
            var books = MockBooks.children(of: q["parentid"]!)!
            if q["sortby"]?.contains("DateCreated") == true { books.reverse() }
            return page(books)
        case (_, "/Items/Latest") where q["parentid"] == MockBooks.viewId:
            return json(MockBooks.files)
        case (_, "/Items/Latest"):
            let source = q["parentid"] == MockCatalog.showsViewId ? catalog.series : catalog.movies
            return json(Array(source.prefix(Int(q["limit"] ?? "") ?? 16)))
        case (_, "/Genres"):
            return json(ItemsPage(items: catalog.genres.map { BaseItem(id: "genre-\($0)", name: $0, kind: .unknown) }, totalRecordCount: catalog.genres.count))
        case (_, "/Items"):
            return page(filterItems(q, catalog))
        case ("POST", let p) where p.hasPrefix("/Sessions"):
            return (204, Data(), "text/plain")
        case ("POST", let p) where p.hasPrefix("/UserItems/") && p.hasSuffix("/UserData"):
            return (200, Data("{}".utf8), "application/json")
        case ("POST", let p) where p.hasPrefix("/UserPlayedItems") || p.hasPrefix("/UserFavoriteItems"):
            return json(UserItemData(played: true))
        default:
            break
        }

        // Parameterised routes
        if path == "/QuickConnect/Authorize" { return (204, Data(), "text/plain") }
        // Display preferences (Bumper syncs its queue there), kept in memory.
        if parts.count == 2, parts[0] == "DisplayPreferences" {
            if request.httpMethod == "POST" {
                let body = request.httpBody ?? request.httpBodyStream.map { s in s.open(); defer { s.close() }; var d = Data(); var buf = [UInt8](repeating: 0, count: 4096); while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }; return d } ?? Data()
                MockMedia.preferences.withLock { $0 = body }
                return (204, Data(), "text/plain")
            }
            let stored = MockMedia.preferences.withLock { $0 }
            return (200, stored.isEmpty ? Data(#"{"Id":"bumper","CustomPrefs":{}}"#.utf8) : stored, "application/json")
        }
        // The server's subtitle search (RemoteSearch) and the files it saves.
        if parts.count == 5, parts[0] == "Items", parts[2] == "RemoteSearch", parts[3] == "Subtitles" {
            if request.httpMethod == "POST" {
                MockMedia.downloadedSubtitles.withLock { $0[parts[1], default: []].append(parts[4]) }
                return (204, Data(), "text/plain")
            }
            return json(MockMedia.remoteSubtitles(itemId: parts[1]))
        }
        if parts.count >= 6, parts[0] == "Videos", parts[3] == "Subtitles", parts.last?.hasPrefix("Stream") == true {
            return (200, MockMedia.subtitleFile(), "application/x-subrip")
        }
        if parts.count >= 2, parts[0] == "Items" {
            let id = parts[1]
            if parts.count >= 4, parts[2] == "Images" {
                let width = Int(q["maxwidth"] ?? "") ?? 400
                let square = id.hasPrefix("book-") || id == MockBooks.viewId
                return (200, image(for: "\(id)-\(parts[3])", width: width, aspect: square ? 1 : parts[3] == "Primary" && !id.contains("-e") ? 1.5 : 0.5625), "image/jpeg")
            }
            if parts.count == 3, parts[2] == "ThemeSongs" {
                let songs = MockMedia.themeSongs(for: id)
                return json(ItemsPage(items: songs, totalRecordCount: songs.count))
            }
            if parts.count == 3, parts[2] == "Similar" {
                return page(Array(catalog.movies.shuffledDeterministic(seed: id.hashValue).prefix(12)))
            }
            if parts.count == 3, parts[2] == "PlaybackInfo" {
                return json(MockMedia.playbackInfo(itemId: id) ?? MockAuth.playbackInfo(itemId: id))
            }
            if let item = MockMedia.item(id: id) ?? MockBooks.item(id: id) ?? catalog.item(id: id) { return json(item) }
            return (404, Data(), "text/plain")
        }
        if parts.count == 3, parts[0] == "Shows", parts[2] == "Seasons" {
            return page(catalog.seasons[parts[1]] ?? [])
        }
        if parts.count == 3, parts[0] == "Shows", parts[2] == "Episodes" {
            // A season's, or (no season asked for) the whole show's, in order.
            if let season = q["seasonid"] { return page(catalog.episodes[season] ?? []) }
            return page((catalog.seasons[parts[1]] ?? []).flatMap { catalog.episodes[$0.id] ?? [] })
        }
        if parts.count == 2, parts[0] == "MediaSegments" {
            let seg = MediaSegment(id: "seg-intro", itemId: parts[1], type: .intro, startTicks: 5 * BaseItem.ticksPerSecond, endTicks: 35 * BaseItem.ticksPerSecond)
            return json(MediaSegmentsPage(items: [seg]))
        }
        return (404, Data(), "text/plain")
    }

    static func filterItems(_ q: [String: String], _ catalog: MockCatalog) -> [BaseItem] {
        if q["parentid"]?.hasPrefix("view-extra-") == true { return [] }     // -mockLibraries: empty libraries
        var items: [BaseItem]
        let types = Set((q["includeitemtypes"] ?? "").split(separator: ",").map(String.init))
        switch q["parentid"] {
        case MockCatalog.moviesViewId: items = catalog.movies
        case MockCatalog.showsViewId: items = types == ["Episode"] ? catalog.episodes.values.flatMap { $0 } : catalog.series
        default:
            if types == ["Episode"] {
                items = catalog.episodes.values.flatMap { $0 }
            } else {
                items = types.contains("Series") && !types.contains("Movie") ? catalog.series : catalog.movies + (types.isEmpty || types.contains("Series") ? catalog.series : [])
                if types.contains("Episode") { items += catalog.episodes.values.flatMap { $0 } }
            }
        }
        if let term = q["searchterm"]?.lowercased(), !term.isEmpty {
            items = items.filter { ($0.name ?? "").lowercased().contains(term) }
        }
        if let genres = q["genres"], !genres.isEmpty {
            let wanted = Set(genres.split(separator: "|").map(String.init))
            items = items.filter { !Set($0.genres ?? []).isDisjoint(with: wanted) }
        }
        if let years = q["years"].map({ Set($0.split(separator: ",").compactMap { Int($0) }) }), !years.isEmpty {
            items = items.filter { $0.productionYear.map(years.contains) ?? false }
        }
        if let min = q["mincommunityrating"].flatMap(Double.init) { items = items.filter { ($0.communityRating ?? 0) >= min } }
        let filters = q["filters"] ?? ""
        if filters.contains("IsUnplayed") { items = items.filter { !$0.isPlayed } }
        if filters.split(separator: ",").contains("IsPlayed") { items = items.filter(\.isPlayed) }
        if filters.contains("IsResumable") { items = items.filter { $0.progress != nil && !$0.isPlayed } }
        if filters.contains("IsFavorite") { items = items.filter { $0.isFavorite } }
        switch q["sortby"] ?? "" {
        case let s where s.contains("DateCreated"): items.sort { ($0.dateCreated ?? $0.premiereDate ?? .distantPast) > ($1.dateCreated ?? $1.premiereDate ?? .distantPast) }
        case let s where s.contains("CommunityRating"): items.sort { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        case let s where s.contains("Random"): items = items.shuffledDeterministic(seed: 42)
        case let s where s.contains("SortName"): items.sort { ($0.name ?? "") < ($1.name ?? "") }
        default: break
        }
        return items
    }

    /// Deterministic generated artwork: a gradient keyed by item id.
    static func image(for key: String, width: Int, aspect: Double) -> Data {
        let cacheKey = "\(key)@\(width)"
        if let hit = imageCache.withLock({ $0[cacheKey] }) { return hit }
        let w = min(max(width, 32), 1920), h = Int(Double(w) * aspect)
        var hasher = SplitMix64(seed: UInt64(bitPattern: Int64(key.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) })))
        func comp() -> CGFloat { CGFloat(hasher.next() % 1000) / 1000 }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = unsafe CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return Data() }
        let c1 = CGColor(red: comp() * 0.7, green: comp() * 0.7, blue: comp() * 0.9, alpha: 1)
        let c2 = CGColor(red: comp() * 0.3, green: comp() * 0.3, blue: comp() * 0.4, alpha: 1)
        let gradient = unsafe CGGradient(colorsSpace: space, colors: [c1, c2] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
        let r = CGFloat(w) * (0.3 + comp() * 0.3)
        ctx.fillEllipse(in: CGRect(x: comp() * CGFloat(w) - r / 2, y: comp() * CGFloat(h) - r / 2, width: r, height: r))
        guard let cg = ctx.makeImage() else { return Data() }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
        let out = data as Data
        imageCache.withLock { $0[cacheKey] = out }
        return out
    }
}

enum MockAuth {
    static var result: AuthenticationResult {
        let json = """
        {"User":{"Id":"\(MockJellyfinProtocol.userId)","Name":"Tester","ServerId":"mock-server","PrimaryImageTag":"avatar1","LastActivityDate":"2026-10-03T19:42:11.1234567Z","LastLoginDate":"2026-09-28T08:15:00.0000000Z","Policy":{"IsAdministrator":true}},"AccessToken":"\(MockJellyfinProtocol.token)","ServerId":"mock-server"}
        """
        return try! JSONDecoder.jellyfin.decode(AuthenticationResult.self, from: Data(json.utf8))
    }

    static func quickConnect(authenticated: Bool) -> QuickConnectState {
        let json = """
        {"Authenticated":\(authenticated),"Secret":"mock-secret","Code":"482 913"}
        """
        return try! JSONDecoder.jellyfin.decode(QuickConnectState.self, from: Data(json.utf8))
    }

    /// Mock playback points at Apple's public HLS test stream (fMP4, HEVC/H.264
    /// ladder) so the native engine and player UI can be exercised end to end.
    static func playbackInfo(itemId: String) -> PlaybackInfoResponse {
        var video = MediaStream(index: 0, type: .video, codec: "hevc")
        video.width = 1920
        video.height = 1080
        video.realFrameRate = 30
        video.videoRangeType = "SDR"
        var audio = MediaStream(index: 1, type: .audio, codec: "aac")
        audio.displayTitle = "English - AAC - Stereo"
        audio.language = "eng"
        var source = MediaSource(id: itemId, container: "hls", mediaStreams: [video, audio])
        source.supportsDirectPlay = false
        source.supportsDirectStream = false
        source.supportsTranscoding = true
        source.transcodingUrl = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
        source.runTimeTicks = 600 * BaseItem.ticksPerSecond
        let json = try! JSONEncoder.jellyfin.encode(["MediaSources": [source]])
        var response = try! JSONDecoder.jellyfin.decode(PlaybackInfoResponse.self, from: json)
        response.playSessionId = "mock-session"
        return response
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (s, atto) = components
        return TimeInterval(s) + TimeInterval(atto) / 1e18
    }
}

extension Array {
    func shuffledDeterministic(seed: Int) -> [Element] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        var copy = self
        for i in stride(from: copy.count - 1, to: 0, by: -1) {
            copy.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        return copy
    }
}
