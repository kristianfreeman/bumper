@testable import AppCore
import Foundation
import JellyfinAPI
import JellyfinMocks
import Synchronization
import Testing

/// Downloads from the mock server: in byte-range pieces, joined in order,
/// byte for byte; the manifest survives losing index.json; removal cleans up.
@MainActor
@Suite("Downloads", .serialized)
struct DownloadStoreTests {
    static func client() -> JellyfinClient {
        MockJellyfinProtocol.latency.withLock { $0 = .zero }
        return JellyfinClient(baseURL: MockJellyfinProtocol.baseURL, clientInfo: ClientInfo(client: "T", device: "D", deviceId: "x", version: "1"),
                              accessToken: MockJellyfinProtocol.token, userId: MockJellyfinProtocol.userId,
                              session: JellyfinClient.makeSession(protocolClasses: [MockJellyfinProtocol.self]))
    }

    static func store(_ dir: URL) -> DownloadStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockJellyfinProtocol.self]
        return DownloadStore(directory: dir, configuration: config, pieceSize: 1024 * 1024)
    }

    static func waitDone(_ store: DownloadStore, _ id: String) async -> DownloadRecord? {
        for _ in 0..<200 {
            if let r = store.record(id), r.isDone || { if case .failed = r.state { return true } else { return false } }() { return r }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return store.record(id)
    }

    @Test func downloadsInPiecesAndJoinsThem() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Self.store(dir)
        let film = BaseItem(id: "film-dl", name: "A Film", kind: .movie)
        store.download([film], client: Self.client(), accountId: "acct")
        let r = try #require(await Self.waitDone(store, film.id))
        #expect(r.state == .done)
        #expect(r.pieces.count == 4)                        // 3 MB in 1 MB pieces
        let file = try #require(store.localFile(for: film.id))
        let data = try Data(contentsOf: file)
        #expect(data.count == MockMedia.downloadSize)
        #expect(data.indices.allSatisfy { data[$0] == MockMedia.downloadByte(film.id, at: $0) })
        #expect(file.lastPathComponent == "media.mp4")

        // index.json lost: rebuilt from the download's own item.json.
        try FileManager.default.removeItem(at: dir.appending(path: "index.json"))
        let again = Self.store(dir)
        #expect(again.localFile(for: film.id) != nil)

        again.remove([film.id])
        #expect(again.record(film.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: film.id).path))
    }

    @Test func downloadsATranscode() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Self.store(dir)
        let film = BaseItem(id: "film-tx", name: "Smaller", kind: .movie)
        store.download([film], client: Self.client(), accountId: "acct", quality: DownloadPreset.small.quality)
        let r = try #require(await Self.waitDone(store, film.id))
        #expect(r.state == .done)
        #expect(r.pieces.count == 1)                       // a transcode comes as one stream
        let data = try Data(contentsOf: try #require(store.localFile(for: film.id)))
        #expect(data.count == MockMedia.downloadSize)
    }

    @Test func aTranscodeDescribesItselfForThePlayer() {
        var source = MediaSource(id: "s", container: "mkv", mediaStreams: [
            MediaStream(index: 0, type: .video, codec: "hevc"), MediaStream(index: 1, type: .audio, codec: "truehd"),
            MediaStream(index: 2, type: .audio, codec: "ac3"), MediaStream(index: 3, type: .subtitle, codec: "subrip"),
            MediaStream(index: 4, type: .subtitle, codec: "pgssub"),
        ])
        source.mediaStreams![0].height = 2160; source.mediaStreams![0].width = 3840
        source.mediaStreams![3].isTextSubtitleStream = true
        source.defaultAudioStreamIndex = 1
        var item = BaseItem(id: "x", name: "X", kind: .movie)
        item.mediaSources = [source]
        let out = DownloadStore.describingTranscode(item, mediaSourceId: "s", maxHeight: 720).mediaSources![0]
        #expect(out.container == "mp4")
        #expect(out.mediaStreams!.map(\.codec) == ["h264", "aac", "webvtt"])     // one audio track; text subtitles only
        #expect(out.mediaStreams![0].height == 720 && out.mediaStreams![0].width == 1280)
    }

    @Test func piecesCoverTheFile() {
        let p = DownloadStore.pieces(size: 10, ranges: true, pieceSize: 4)
        #expect(p.map(\.range) == [0...3, 4...7, 8...9])
        #expect(DownloadStore.pieces(size: 10, ranges: false, pieceSize: 4).map(\.range) == [nil])
        #expect(DownloadStore.pieces(size: nil, ranges: true, pieceSize: 4).map(\.range) == [nil])
    }
}

/// Progress the server didn't get is kept, and goes once it can.
@Suite("Playstate outbox")
struct PlaystateOutboxTests {
    @Test func keepsTheLatestAndDelivers() async {
        let defaults = UserDefaults(suiteName: "outbox-test-\(UUID().uuidString)")!
        let outbox = PlaystateOutbox(defaults: defaults, account: "a")
        outbox.keep(itemId: "e1", positionTicks: 100, played: false)
        outbox.keep(itemId: "e1", positionTicks: 200, played: false)
        outbox.keep(itemId: "e2", positionTicks: 0, played: true)
        #expect(outbox.entries.count == 2)
        #expect(outbox.entries.first { $0.itemId == "e1" }?.positionTicks == 200)
        await outbox.deliver(with: await DownloadStoreTests.client())
        #expect(outbox.entries.isEmpty)
    }
}
