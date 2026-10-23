import Foundation
import JellyfinAPI
import JellyfinMocks
import Synchronization
import Testing
@testable import AppFeatures

/// A library's rows past its first few: titles at once, cards as each comes
/// near, and a row with nothing in it gone.
@MainActor
@Suite("Shelves", .serialized)
struct ShelvesTests {
    static func client() -> JellyfinClient {
        MockJellyfinProtocol.latency.withLock { $0 = .zero }
        return JellyfinClient(baseURL: MockJellyfinProtocol.baseURL, clientInfo: ClientInfo(client: "T", device: "D", deviceId: "x", version: "1"),
                              accessToken: MockJellyfinProtocol.token, userId: MockJellyfinProtocol.userId,
                              session: JellyfinClient.makeSession(protocolClasses: [MockJellyfinProtocol.self]))
    }

    @Test func aLibrarysRowsFillAsTheyComeNearAndEmptyOnesGo() async throws {
        let client = Self.client()
        let movies = try #require(try await client.userViews().items.first { $0.collectionType == "movies" })
        let rows = await Shelves.library(movies, collections: nil, client: client)
        #expect(rows.contains { $0.id.hasPrefix("genre-") }, "no genre rows")
        #expect(rows.contains { $0.id.hasSuffix("decade-1950") }, "no decades")
        #expect(rows.allSatisfy { $0.items.isEmpty }, "rows loaded before they came near")

        let shelves = LazyShelves()
        shelves.replace(rows)
        let genre = try #require(rows.first { $0.id.hasPrefix("genre-") })
        await shelves.near(genre.id, client: client)
        #expect(shelves.sections.first { $0.id == genre.id }?.items.isEmpty == false)
        // A row nothing's in: asked for, empty, gone.
        var nothing = ItemQuery(includeItemTypes: [.movie], limit: 24)
        nothing.genres = ["No Such Genre"]
        shelves.replace(shelves.sections + [Shelves.shelf("empty", "Nothing", subtitle: nil, nothing)])
        await shelves.near("empty", client: client)
        #expect(!shelves.sections.contains { $0.id == "empty" })
    }
}
