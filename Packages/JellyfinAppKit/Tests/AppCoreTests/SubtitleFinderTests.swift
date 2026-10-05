import Foundation
import JellyfinAPI
import Testing
@testable import AppCore

struct SubtitleRankingTests {
    let file = SubtitleFile(title: "Movie", year: 2012, fileName: "Movie.2012.1080p.BluRay.x264-SPARKS.mkv", fps: 23.976)

    /// The same rules as the service's heuristic (services/search/src/subtitles.ts).
    @Test func hashMatchFirstThenTheReleaseGroupAndFrameRate() {
        let ranked = SubtitleRanking.rank([
            RemoteSubtitle(id: "popular", name: "Movie.2012.720p.WEB-OTHER", frameRate: 25, downloadCount: 9000),
            RemoteSubtitle(id: "group", name: "Movie.2012.1080p.BluRay.x264-SPARKS", frameRate: 23.976, downloadCount: 300),
            RemoteSubtitle(id: "hash", name: "whatever", downloadCount: 5, isHashMatch: true),
        ], for: file)
        #expect(ranked.map(\.id) == ["hash", "group", "popular"])
        #expect(ranked[0].reasons.first == "Made for this exact file")
        #expect(ranked[1].reasons == ["Same release group (SPARKS)", "Frame rate matches"])
        #expect(ranked[2].reasons == ["Made for 25 fps"])
        #expect(ranked[1].confidence <= 0.85)                        // only a hash match is "sure"
    }

    @Test func withoutTheServiceTheDeviceRanks() async {
        let (results, judgedBy) = await SubtitleRanker(base: nil).rank([RemoteSubtitle(id: "a", name: "x")], for: file)
        #expect(judgedBy == "device" && results.count == 1)
    }
}
