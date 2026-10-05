@testable import AppCore
import CoreGraphics
import Foundation
import ImageIO
import Instrumentation
@testable import JellyfinAPI
@testable import JellyfinMocks
import Testing

@Suite("BlurHash")
struct BlurHashTests {
    @Test func decodesToRequestedSize() throws {
        let image = try #require(BlurHash.image("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 32, height: 20))
        #expect(image.width == 32 && image.height == 20)
    }

    @Test(arguments: ["", "abc", "LEHV6nWB2yk8pyo0adR*.7kCMdn"])
    func rejectsMalformedHashes(hash: String) {
        #expect(BlurHash.image(hash) == nil)
    }

    @Test(.enabled(if: isOptimized, "timing budget: optimized builds only")) func decodeIsWellUnderOneMillisecond() {
        _ = BlurHash.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 24, height: 24, punch: 1)
        let t = ContinuousClock().measure {
            for _ in 0..<200 { _ = BlurHash.decode("LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 24, height: 24, punch: 1) }
        }
        #expect(t / 200 < .milliseconds(1), "blurhash took \(t / 200) per decode")
    }
}

@Suite("Image pipeline")
struct ImagePipelineTests {
    func jpeg(width: Int, height: Int) -> Data {
        MockJellyfinProtocol.respond(to: URLRequest(url: URL(string: "http://mock.jellyfin.local/Items/x/Images/Backdrop?maxWidth=\(width)")!)).1
    }

    @Test func downsamplesToTargetPixelSize() throws {
        let data = jpeg(width: 1920, height: 1080)
        let image = try ImagePipeline.decode(data, maxPixelSize: 400)
        #expect(max(image.width, image.height) == 400)
    }

    @Test(.enabled(if: isOptimized, "timing budget: optimized builds only")) func cardDecodeFitsBudget() throws {
        let data = jpeg(width: 512, height: 768)
        _ = try ImagePipeline.decode(data, maxPixelSize: 456)
        let t = try ContinuousClock().measure {
            for _ in 0..<20 { _ = try ImagePipeline.decode(data, maxPixelSize: 456) }
        }
        #expect(t / 20 < .milliseconds(12), "card decode \(t / 20)")
    }

    @Test func memoryCacheEvictsLeastRecentlyUsed() throws {
        let image = try ImagePipeline.decode(jpeg(width: 256, height: 144), maxPixelSize: 256)
        let cost = image.bytesPerRow * image.height
        let cache = MemoryCache(costLimit: cost * 3)
        cache.set(image, for: "a")
        cache.set(image, for: "b")
        cache.set(image, for: "c")
        _ = cache.get("a")              // touch a: b is now the oldest
        cache.set(image, for: "d")      // over budget → evict down to 80%
        #expect(cache.get("a") != nil)
        #expect(cache.get("d") != nil)
        #expect(cache.get("b") == nil)
    }

    @Test func requestKeyIgnoresAuthToken() {
        let a = ImageRequest(url: URL(string: "http://s/Items/1/Images/Primary?tag=x&api_key=one")!, maxPixelSize: 300)
        let b = ImageRequest(url: URL(string: "http://s/Items/1/Images/Primary?tag=x&api_key=two")!, maxPixelSize: 300)
        #expect(a.key == b.key)
    }
}

@Suite("Content cache")
struct ContentCacheTests {
    @Test func roundTripsCodableValues() async {
        let cache = ContentCache(name: "test-\(UUID().uuidString)")
        await cache.store(["a", "b"], for: "k")
        #expect(await cache.value([String].self, for: "k") == ["a", "b"])
        await cache.removeAll()
        #expect(await cache.value([String].self, for: "k") == nil)
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

@Suite("Perf recorder")
struct PerfRecorderTests {
    @Test func writesSnapshotWithDeviceAndBudgets() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Own Metrics: other suites record into .shared in parallel.
        let metrics = Metrics()
        let recorder = PerfRecorder(directory: dir, metrics: metrics)
        metrics.record(.homeLoad, value: 123)
        recorder.writeIfChanged()
        let data = try Data(contentsOf: recorder.latestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try decoder.decode(PerfRecorder.Snapshot.self, from: data)
        #expect(!snap.device.isEmpty)
        #expect(snap.metrics["home.load"] != nil)
        // Unchanged metrics → no rewrite.
        let before = try FileManager.default.attributesOfItem(atPath: recorder.latestURL.path)[.modificationDate] as? Date
        recorder.writeIfChanged()
        let after = try FileManager.default.attributesOfItem(atPath: recorder.latestURL.path)[.modificationDate] as? Date
        #expect(before == after)
    }
}

@MainActor @Suite struct DefaultThemeTests {
    @Test func bumperUntilSomeonePicksAnother() {
        let defaults = UserDefaults(suiteName: "theme-\(UUID())")!
        #expect(AppSettings(defaults: defaults).themeId == "bumper")
        AppSettings(defaults: defaults).themeId = "abyss"
        #expect(AppSettings(defaults: defaults).themeId == "abyss")
    }
}

@MainActor @Suite struct LibraryUsageTests {
    let movies = { var b = BaseItem(id: "m", name: "Movies", kind: .collectionFolder); b.collectionType = "movies"; return b }()
    let shows = { var b = BaseItem(id: "s", name: "Shows", kind: .collectionFolder); b.collectionType = "tvshows"; return b }()
    let books = { var b = BaseItem(id: "b", name: "Audiobooks", kind: .collectionFolder); b.collectionType = "books"; return b }()

    @Test func filmsAndShowsFirstThenWhatYouUse() {
        let usage = LibraryUsage(defaults: UserDefaults(suiteName: "usage-\(UUID())")!)
        #expect(usage.ordered([books, shows, movies]).map(\.id) == ["m", "s", "b"])   // no history: by kind
        usage.recordPlay(BaseItem(id: "x", name: "A book", kind: .audioBook), libraries: [books, shows, movies])
        usage.record("s", weight: LibraryUsage.openWeight)
        #expect(usage.ordered([books, shows, movies]).map(\.id) == ["b", "s", "m"])   // played beats opened
    }
}

@Suite struct AuthorizationHeaderTests {
    @Test func deviceNamesBecomePlainASCII() {
        let info = ClientInfo(client: "Bumper", device: "Kristian’s MacBook Pro · Café", deviceId: "abc", version: "0.1.0")
        let header = info.authorizationHeader(token: nil)
        #expect(header.contains(#"Device="Kristian's MacBook Pro  Cafe""#))
        #expect(header.unicodeScalars.allSatisfy { $0.isASCII })
    }
}
