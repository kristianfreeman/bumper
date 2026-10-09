import Foundation
import Network
import Instrumentation
@testable import JellyfinAPI
@testable import JellyfinMocks
import Synchronization
import Testing

@Suite("Models & decoding")
struct DecodingTests {
    @Test func decodesPascalCaseItemWithSevenDigitFractionalDates() throws {
        let json = """
        {"Id":"abc","Name":"Arrival","Type":"Movie","ProductionYear":2016,"RunTimeTicks":69600000000,
         "PremiereDate":"2016-11-10T00:00:00.0000000Z",
         "UserData":{"PlaybackPositionTicks":12000000000,"Played":false,"IsFavorite":true,"LastPlayedDate":"2024-01-02T03:04:05.1234567Z"},
         "ImageTags":{"Primary":"t1"},"BackdropImageTags":["b1"],
         "ImageBlurHashes":{"Primary":{"t1":"LEHV6nWB2yk8pyo0adR*.7kCMdnj"}}}
        """
        let item = try JSONDecoder.jellyfin.decode(BaseItem.self, from: Data(json.utf8))
        #expect(item.kind == .movie)
        #expect(item.runtime == .seconds(6960))
        #expect(item.resumePosition == .seconds(1200))
        #expect(item.isFavorite)
        #expect(item.blurHash(for: .primary, tag: "t1") != nil)
        let lastPlayed = try #require(item.userData?.lastPlayedDate)
        #expect(abs(lastPlayed.timeIntervalSince1970 - 1_704_164_645.1234567) < 0.001)
    }

    @Test func unknownItemKindsDoNotFailThePage() throws {
        let json = #"{"Items":[{"Id":"1","Type":"SomethingNew"},{"Id":"2","Type":"Movie"}],"TotalRecordCount":2}"#
        let page = try JSONDecoder.jellyfin.decode(ItemsPage.self, from: Data(json.utf8))
        #expect(page.items.map(\.kind) == [.unknown, .movie])
    }

    @Test func ticksRoundTrip() {
        #expect(Duration.ticks(10_000_000) == .seconds(1))
        #expect(Duration.seconds(90).ticks == 900_000_000)
    }

    @Test(arguments: [("10.11.11", true), ("10.11.0", true), ("10.10.7", false), ("12.0", true), ("garbage", false)])
    func serverVersionGate(version: String, supported: Bool) {
        #expect(PublicSystemInfo(id: nil, serverName: nil, version: version).isSupported == supported)
    }

    @Test func dolbyVisionAndAtmosDetection() {
        var v = MediaStream(index: 0, type: .video, codec: "hevc")
        v.videoRangeType = "DOVIWithHDR10"
        #expect(v.isDolbyVision)
        var a = MediaStream(index: 1, type: .audio, codec: "eac3")
        a.audioSpatialFormat = "DolbyAtmos"
        #expect(a.isAtmos)
    }
}

@Suite("Request building")
struct RequestTests {
    let client = JellyfinClient(baseURL: URL(string: "http://nas.local:8096/jellyfin")!, clientInfo: ClientInfo(client: "Test", device: "TV", deviceId: "dev", version: "1"), accessToken: "tok", userId: "u1")

    @Test func preservesBasePathAndEncodesPlus() {
        let url = client.url("/Items", query: [.init(name: "searchTerm", value: "C++ & more")])
        #expect(url.absoluteString == "http://nas.local:8096/jellyfin/Items?searchTerm=C%2B%2B%20%26%20more")
    }

    @Test func authorizationHeaderUsesMediaBrowserScheme() {
        #expect(client.authorizationHeader == #"MediaBrowser Client="Test", Device="TV", DeviceId="dev", Version="1", Token="tok""#)
    }

    @Test func directStreamIsStaticAndAuthenticated() {
        let url = client.directStreamURL(itemId: "i", mediaSourceId: "m", container: "mkv,webm", playSessionId: "p")
        #expect(url.path() == "/jellyfin/Videos/i/stream.mkv")
        #expect(url.query()?.contains("static=true") == true)
        #expect(url.query()?.contains("api_key=tok") == true)
    }

    @Test func filmographyAsksForTheirFilmsAndShowsNewestFirst() {
        let q = Dictionary(uniqueKeysWithValues: ItemQuery.filmography(personId: "p1", roles: ["Actor", "GuestStar"]).queryItems(userId: "u1").map { ($0.name, $0.value ?? "") })
        #expect(q["personIds"] == "p1")
        #expect(q["personTypes"] == "Actor,GuestStar")
        #expect(q["includeItemTypes"] == "Movie,Series")
        #expect(q["sortBy"] == "ProductionYear,PremiereDate,SortName")
        #expect(q["sortOrder"] == "Descending")
        #expect(q["recursive"] == "true")
        // Without a person, neither is sent.
        #expect(!ItemQuery().queryItems(userId: "u1").contains { $0.name == "personIds" || $0.name == "personTypes" })
    }

    @Test func absoluteURLHandlesServerRelativeAndAbsolute() {
        #expect(client.absoluteURL(serverRelative: "/videos/x/master.m3u8?a=1")?.absoluteString == "http://nas.local:8096/jellyfin/videos/x/master.m3u8?a=1")
        #expect(client.absoluteURL(serverRelative: "https://cdn/x.m3u8")?.absoluteString == "https://cdn/x.m3u8")
    }
}

@Suite("Mock server round trips", .serialized)
struct MockServerTests {
    let client: JellyfinClient = {
        MockJellyfinProtocol.latency.withLock { $0 = .zero }
        return JellyfinClient(baseURL: MockJellyfinProtocol.baseURL, clientInfo: ClientInfo(client: "T", device: "D", deviceId: "x", version: "1"),
                              accessToken: MockJellyfinProtocol.token, userId: MockJellyfinProtocol.userId,
                              session: JellyfinClient.makeSession(protocolClasses: [MockJellyfinProtocol.self]))
    }()

    /// Search asks for each kind on its own: a show is found by its name
    /// first among the shows, and no kind takes more than its share.
    @Test func searchFindsAShowByItsNameEachKindOnItsOwn() async throws {
        let shows = try await client.items(ItemQuery(includeItemTypes: [.series], limit: 5)).items
        let show = try #require(shows.first)
        let name = try #require(show.name)
        let found = try await client.search(name, limit: 6).items
        #expect(found.first { $0.kind == .series }?.id == show.id)
        for kind in [ItemKind.movie, .series, .episode, .boxSet] {
            #expect(found.filter { $0.kind == kind }.count <= 6)
        }
    }

    @Test func homeEndpoints() async throws {
        async let views = client.userViews()
        async let resume = client.resumeItems()
        async let latest = client.latest(parentId: MockCatalog.moviesViewId)
        let (v, r, l) = try await (views, resume, latest)
        #expect(v.items.count >= 2)   // movies + shows (+ test media when configured)
        #expect(!r.items.isEmpty)
        #expect(!l.isEmpty)
    }

    /// A cast member's page: who they are, and what they're in, newest first.
    @Test func personAndFilmography() async throws {
        let film = try await client.item(id: "movie-0001")
        let people = try #require(film.people)
        #expect(people.contains { $0.type == "Director" } && people.contains { $0.type == "Actor" })
        let actor = try #require(people.first { $0.type == "Actor" })
        let person = try await client.item(id: actor.id, fields: ItemField.person)
        #expect(person.kind == .person && person.name == actor.name)
        let titles = try await client.items(.filmography(personId: actor.id)).items
        #expect(titles.contains { $0.id == "movie-0001" })
        #expect(titles.allSatisfy { MockPeople.people(for: $0.id).contains { $0.id == actor.id } })
        let years = titles.compactMap(\.productionYear)
        #expect(years == years.sorted(by: >))
        // Counted by role: the actor who directs (person-a02) is both.
        var directed = ItemQuery.filmography(personId: "person-a02", roles: ["Director"])
        directed.limit = 0
        #expect(try await client.items(directed).totalRecordCount > 0)
    }

    /// Film 1 has a trailer in the library and extras; film 2 has neither.
    @Test func trailersAndExtras() async throws {
        let trailers = try await client.localTrailers(itemId: "movie-0001")
        #expect(trailers.count == 1 && trailers[0].kind.isPlayable)
        #expect(try await client.item(id: trailers[0].id).id == trailers[0].id)       // it opens like anything else
        #expect(try await client.item(id: "movie-0001").remoteTrailers?.isEmpty == false)
        let extras = try await client.specialFeatures(itemId: "movie-0001")
        #expect(extras.map(\.extraType) == ["BehindTheScenes", "DeletedScene", "Featurette", "Interview"])
        #expect(try await client.localTrailers(itemId: "movie-0002").isEmpty)
        #expect(try await client.specialFeatures(itemId: "movie-0002").isEmpty)
        #expect(try await client.item(id: "movie-0002").remoteTrailers == nil)
    }

    @Test func pagingReportsTotals() async throws {
        var q = ItemQuery(parentId: MockCatalog.moviesViewId, includeItemTypes: [.movie])
        q.startIndex = 100
        q.limit = 50
        let page = try await client.items(q)
        #expect(page.totalRecordCount == 600)
        #expect(page.items.count == 50)
    }
}

@Suite("Performance")
struct DecodePerformanceTests {
    /// A 500-item page (a big "See All" grid page) must decode well inside a frame.
    @Test(.enabled(if: isOptimized, "timing budget: optimized builds only")) func largePageDecodesUnderBudget() throws {
        let page = ItemsPage(items: Array(MockCatalog.shared.movies.prefix(500)), totalRecordCount: 500)
        let data = try JSONEncoder.jellyfin.encode(page)
        let decoder = JSONDecoder.jellyfin
        _ = try decoder.decode(ItemsPage.self, from: data) // warm
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<10 {
            let t = try clock.measure { _ = try decoder.decode(ItemsPage.self, from: data) }
            samples.append(t.milliseconds)
        }
        let median = samples.sorted()[samples.count / 2]
        print("500-item page decode median: \(median) ms (\(data.count / 1024) KB)")
        #expect(median < 40, "500-item decode took \(median) ms")
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

@Suite("Mock HTTP server (real sockets)", .serialized)
struct MockHTTPServerTests {
    @Test func servesTheAPIOverLoopback() async throws {
        let server = MockHTTPServer()
        defer { server.stop() }
        let base = try server.start()   // ephemeral port: immune to stale processes
        MockJellyfinProtocol.latency.withLock { $0 = .zero }
        let client = JellyfinClient(baseURL: base, clientInfo: ClientInfo(client: "T", device: "D", deviceId: "x", version: "1"),
                                    accessToken: MockJellyfinProtocol.token, userId: MockJellyfinProtocol.userId)
        let info = try await client.publicSystemInfo()
        #expect(info.version == "10.11.11")
        // Keep-alive: several requests on the same session.
        for _ in 0..<5 { #expect(try await client.userViews().items.count >= 2) }
        // Queries with characters URL(string:) rejects must not crash the server.
        var q = ItemQuery(parentId: MockCatalog.moviesViewId, includeItemTypes: [.movie])
        q.genres = ["Action", "Science Fiction"]
        _ = try await client.items(q)
        let raw = try await URLSession.shared.data(from: base.appending(path: "Items").appending(queryItems: [.init(name: "genres", value: "A|B"), .init(name: "searchTerm", value: "a b")]))
        #expect((raw.1 as? HTTPURLResponse)?.statusCode == 200)
    }
}

@Suite("Mock HTTP server framing", .serialized)
struct MockHTTPFramingTests {
    /// Headers and body in separate TCP writes, then a second request on the
    /// same keep-alive connection — the case that wedged autoplay.
    @Test func bodySplitAcrossSegmentsKeepsConnectionUsable() async throws {
        let server = MockHTTPServer()
        defer { server.stop() }
        let base = try server.start()
        let port = UInt16(base.port!)
        let response: String = try await withCheckedThrowingContinuation { cont in
            // Resume exactly once: on the answer, on a socket error, or at the
            // 5 s deadline (which also cancels the socket) — never hang.
            let once = Mutex(false)
            func finish(_ r: Result<String, any Error>) {
                guard once.withLock({ done in defer { done = true }; return !done }) else { return }
                cont.resume(with: r)
            }
            let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                conn.cancel()
                finish(.failure(URLError(.timedOut)))
            }
            conn.start(queue: .global())
            let body = #"{"PlayableMediaTypes":["Video"]}"#
            let head = "POST /Sessions/Capabilities/Full HTTP/1.1\r\nHost: x\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
            let second = "GET /System/Info/Public HTTP/1.1\r\nHost: x\r\n\r\n"
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    conn.send(content: Data((body + second).utf8), completion: .contentProcessed { _ in })
                }
            })
            let received = Mutex(Data())
            func read() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    let text = received.withLock { buf in
                        if let data { buf.append(data) }
                        return String(decoding: buf, as: UTF8.self)
                    }
                    if text.contains("10.11.11") { conn.cancel(); finish(.success(text)) }
                    else if let error { finish(.failure(error)) }
                    else if isComplete { finish(.failure(URLError(.networkConnectionLost))) }
                    else { read() }
                }
            }
            read()
        }
        #expect(response.components(separatedBy: "HTTP/1.1 ").count - 1 == 2, "both requests answered on one connection")
    }
}

@Suite("Mock media ranges", .serialized)
struct MockMediaRangeTests {
    @Test func honoursBothEndsOfRangesLikeAVFoundationExpects() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mockmedia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 7, count: 10_000).write(to: dir.appending(path: "a.mp4"))
        let manifest = #"[{"file":"a.mp4","name":"A","container":"mp4","duration":1,"audio":[],"subtitles":[]}]"#
        try Data(manifest.utf8).write(to: dir.appending(path: "manifest.json"))
        MockMedia.configure(directory: dir)
        defer { MockMedia.reset() }

        let probe = try #require(MockMedia.stream(itemId: "media-0", range: "bytes=0-1"))
        #expect(probe.0 == 206 && probe.1.count == 2)
        #expect(probe.2["Content-Range"] == "bytes 0-1/10000")
        #expect(probe.2["Content-Type"] == "video/mp4")

        let open = try #require(MockMedia.stream(itemId: "media-0", range: "bytes=9000-"))
        #expect(open.1.count == 1_000 && open.2["Content-Range"] == "bytes 9000-9999/10000")

        #expect(MockMedia.stream(itemId: "media-0", range: "bytes=20000-")?.0 == 416)
    }
}

@Suite("Skip segments")
struct SegmentTests {
    @Test func unknownSegmentTypeDoesNotFailTheList() throws {
        let json = #"{"Items":[{"Id":"a","ItemId":"i","Type":"Intro","StartTicks":0,"EndTicks":10},{"Id":"b","ItemId":"i","Type":"Sponsor","StartTicks":20,"EndTicks":30},{"Id":"c","ItemId":"i","Type":"outro","StartTicks":40,"EndTicks":50}]}"#
        let page = try JSONDecoder().decode(MediaSegmentsPage.self, from: Data(json.utf8))
        #expect(page.items.map(\.type) == [.intro, .unknown, .outro])
    }

    @Test func segmentsFromChapterNames() {
        let t = BaseItem.ticksPerSecond
        let chapters = [
            Chapter(startPositionTicks: 0, name: "Previously On"),
            Chapter(startPositionTicks: 40 * t, name: "Opening"),
            Chapter(startPositionTicks: 130 * t, name: "Chapter 2"),
            Chapter(startPositionTicks: 1300 * t, name: "End Credits"),
        ]
        let segs = MediaSegment.fromChapters(chapters, itemId: "e", runtimeTicks: 1380 * t)
        #expect(segs.map(\.type) == [.recap, .intro, .outro])
        #expect(segs[1].startTicks == 40 * t && segs[1].endTicks == 130 * t)
        #expect(segs[2].endTicks == 1380 * t)                  // last chapter runs to the end
        #expect(MediaSegment.kind(forChapter: "Operation") == nil)  // "op" only as a word
    }
}

@Suite("Search order")
struct SearchOrderTests {
    static func titles(_ names: [String]) -> [BaseItem] { names.enumerated().map { BaseItem(id: "\($0.offset)", name: $0.element, kind: .series) } }

    @Test func theNameThatIsTheTermComesFirstIgnoringTheThe() {
        let items = Self.titles(["Simpsons Roasting on an Open Fire", "Homer's Simpsons Trip", "The Simpsons", "Something Else"])
        #expect(JellyfinClient.bestFirst(items, for: "simpsons").map(\.name) ==
                ["The Simpsons", "Simpsons Roasting on an Open Fire", "Homer's Simpsons Trip", "Something Else"])
    }

    @Test func equalMatchesKeepTheServersOrder() {
        let items = Self.titles(["Café Society", "Cafe Racer", "Le Café"])
        #expect(JellyfinClient.bestFirst(items, for: "cafe").map(\.name) == ["Café Society", "Cafe Racer", "Le Café"])
    }
}
