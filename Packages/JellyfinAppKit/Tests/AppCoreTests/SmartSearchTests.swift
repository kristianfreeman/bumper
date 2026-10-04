import Foundation
import Testing
@testable import AppCore
import JellyfinAPI

/// Answers like services/search: HEAD → `status`, POST → `intent`.
final class StubService: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 204
    nonisolated(unsafe) static var intent = #"{"v":1,"kind":"browse","media":"movie","genre":"science_fiction","decade":1980,"watched":"unwatched","added":"any","source":"jev"}"#
    nonisolated(unsafe) static var posts = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let isHead = request.httpMethod == "HEAD"
        if !isHead { Self.posts += 1 }
        let code = isHead ? Self.status : (Self.status == 204 ? 200 : Self.status)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        if !isHead { client?.urlProtocol(self, didLoad: Data(Self.intent.utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct SmartSearchTests {
    let everything = CollectionFilter(base: ItemQuery(includeItemTypes: [.movie, .series]), libraryName: "Everything")

    func service() -> SmartSearch {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubService.self]
        return SmartSearch(endpoint: URL(string: "https://search.test/v1/interpret")!, configuration: config)
    }

    @Test func theServiceReadingBecomesTheFilter() async {
        StubService.status = 204
        let result = await service().understand("an 80s sci-fi film I haven't seen", in: everything, genres: ["Sci-Fi", "Drama"])
        guard case .filter(let filter, let changed, true) = result else { Issue.record("got \(result)"); return }
        #expect(filter.sentence == "Movies · unwatched · sci-fi · from the 1980s")      // the library's own genre name
        #expect(filter.query.includeItemTypes == [.movie])
        #expect(Set(changed) == [.watched, .genre, .decade])
    }

    @Test func whenTheServiceIsOffTheDeviceReadsTheWords() async {
        StubService.status = 503
        StubService.posts = 0
        let result = await service().understand("something funny from the 90s", in: everything)
        guard case .filter(let filter, _, false) = result else { Issue.record("got \(result)"); return }
        #expect(filter.genre == "Comedy" && filter.decade == 1990)
        #expect(StubService.posts == 0)                                                   // the health check said no
        #expect(await SmartSearch(endpoint: nil).understand("the dark knight", in: everything) == .title("the dark knight"))
    }
}
