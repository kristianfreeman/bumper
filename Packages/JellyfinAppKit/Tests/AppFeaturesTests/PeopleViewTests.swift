#if os(macOS)                    // in-process view tests: the Mac's `swift test`
@testable import AppFeatures
import AppCore
import Foundation
import JellyfinAPI
import PlaybackCore
import Testing

extension OnScreen {
    /// People, trailers and extras on a film's page (UITests/PeopleTests,
    /// iPhoneUITests/PhonePeopleTests: reaching them with focus and swipes
    /// stays there). In the mock, film 1 has a trailer in the library, one
    /// online and four extras; film 2 has none; person-a02 acts and directs.
    @Suite("People, trailers and extras")
    struct People {
        @Test func aFilmsPageShowsItsCastAndCrew() async throws {
            let screen = Screen(route: "item:movie-0001")
            try await screen.wait(forText: "Cast & Crew")
            // The cast, then the crew, in the server's order.
            let people = screen.elements(prefix: "person.").map(\.id)
            #expect(people.prefix(5) == ["person.person-a01", "person.person-a10", "person.person-a27", "person.person-a42", "person.person-d01"])
        }

        @Test func aCastCardOpensTheirPage() async throws {
            let screen = Screen(route: "item:movie-0001")
            let card = try await screen.wait(for: "person.person-a01")
            try await screen.press(card.id)
            let name = try await screen.wait(for: "person.name")
            #expect(!name.text.isEmpty && card.text.contains(name.text), "opened \(name.text), not the card's \(card.text)")
            try await screen.wait(forAny: "person.item.")                 // their films and shows
        }

        @Test func aPersonPageSaysWhatTheyreKnownForWithTheirBioAndTitlesNewestFirst() async throws {
            let screen = Screen(route: "person:person-a02")
            try await screen.wait(for: "person.knownFor") { $0.text.contains("Actor") && $0.text.contains("Director") }
            #expect(screen.element("person.name")?.text.isEmpty == false)
            #expect(screen.element("person.bio")?.text.isEmpty == false)
            let titles = try await screen.wait(forAny: "person.item.")
            let client = try #require(screen.app.session?.client)
            var years: [Int] = []
            for id in titles.map({ String($0.id.dropFirst("person.item.".count)) }) {
                years.append(try await client.item(id: id).productionYear ?? 0)
            }
            #expect(years.count > 1)
            #expect(years == years.sorted(by: >), "not newest first: \(years)")
        }

        @Test func aFilmWithExtrasHasATrailerAndAnExtrasRow() async throws {
            let screen = Screen(route: "item:movie-0001")
            try await screen.wait(for: "detail.trailer")
            try await screen.wait(forText: "Extras")
            #expect(screen.elements(prefix: "extra.movie-0001-extra-").count == 4)
        }

        @Test func theTrailerPlays() async throws {
            let screen = Screen(route: "item:movie-0001")
            try await screen.press("detail.trailer")
            try await screen.waitUntil("movie-0001-trailer to play") { screen.engine?.plan?.item.id == "movie-0001-trailer" }
        }

        /// Film 3's only trailer is online: off the TV it's a link (held by
        /// the harness, never opened).
        @Test func aTrailerOnlyOnlineIsALink() async throws {
            let screen = Screen(route: "item:movie-0003")
            screen.expectsLinks = true
            try await screen.press("detail.trailer")
            try await screen.waitUntil("the link") { !screen.links.isEmpty }
            #expect(screen.links.map { $0.host() ?? "" } == ["www.youtube.com"], "\(screen.links)")
            #expect(screen.app.playback == nil)
        }

        @Test func anExtraPlays() async throws {
            let screen = Screen(route: "item:movie-0001")
            try await screen.press("extra.movie-0001-extra-1")
            try await screen.waitUntil("movie-0001-extra-1 to play") { screen.engine?.plan?.item.id == "movie-0001-extra-1" }
        }

        @Test func aFilmWithoutThemHasNoTrailerOrExtras() async throws {
            let screen = Screen(route: "item:movie-0002")
            try await screen.wait(forText: "More Like This")                 // the page is in…
            try await screen.settle()                                         // …and anything after it
            #expect(screen.element("detail.trailer") == nil)
            #expect(screen.text("Extras") == nil)
        }
    }
}
#endif
