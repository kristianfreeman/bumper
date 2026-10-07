@testable import AppCore
import Foundation
import JellyfinAPI
import Testing

/// A person's page says what they're known for and lists their titles
/// newest first; a film's Trailer button picks the right trailer.
@Suite("People, trailers and extras")
struct PeopleTests {
    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d))!
    }

    static func item(_ name: String, year: Int?, kind: ItemKind = .movie, premiere: Date? = nil) -> BaseItem {
        var i = BaseItem(id: name, name: name, kind: kind)
        i.productionYear = year
        i.premiereDate = premiere
        return i
    }

    @Test func knownForTheRolesTheyHaveTheMostTitlesIn() {
        #expect(PersonWords.knownFor(counts: ["Actor": 12, "Director": 3, "Writer": 0]) == "Actor · Director")
        #expect(PersonWords.knownFor(counts: ["Actor": 2, "Director": 9]) == "Director · Actor")
        #expect(PersonWords.knownFor(counts: ["Writer": 4, "Director": 4]) == "Director · Writer")      // a tie: the usual order
        // Nothing counted: the role on the card that was opened.
        #expect(PersonWords.knownFor(counts: [:], fallback: "GuestStar") == "Actor")
        #expect(PersonWords.knownFor(counts: [:], fallback: nil) == nil)
    }

    @Test func lifeLine() {
        #expect(PersonWords.life(born: Self.date(1971, 5, 4), died: nil, place: "Leeds, England") == "Born 4 May 1971 in Leeds, England")
        #expect(PersonWords.life(born: Self.date(1931, 5, 12), died: Self.date(2016, 3, 2), place: "Cork") == "12 May 1931 – 2 March 2016")
        #expect(PersonWords.life(born: Self.date(1980, 1, 1), died: nil, place: " ") == "Born 1 January 1980")
        #expect(PersonWords.life(born: nil, died: nil, place: nil) == nil)
    }

    @Test func ledeCountsFilmsAndShows() {
        let items = [Self.item("A", year: 2020), Self.item("B", year: 2019), Self.item("S", year: 2018, kind: .series)]
        #expect(PersonWords.lede(items: items) == "Two films and one show in your library.")
        #expect(PersonWords.lede(items: Array(repeating: Self.item("A", year: 1), count: 14)) == "14 films in your library.")
        #expect(PersonWords.lede(items: []) == nil)
    }

    @Test func filmographyNewestFirstUndatedLast() {
        let items = [
            Self.item("Old", year: 1994),
            Self.item("Undated", year: nil),
            Self.item("Beta", year: 2021),
            Self.item("Alpha", year: 2021),
            Self.item("Premiere only", year: nil, premiere: Self.date(2023, 6, 1)),
            Self.item("Show", year: 2010, kind: .series),
        ]
        #expect(PersonWords.filmography(items).map(\.name) == ["Premiere only", "Alpha", "Beta", "Show", "Old", "Undated"])
    }

    @Test func trailerPrefersTheLibrarysOwn() {
        let local = BaseItem(id: "t", name: "Trailer", kind: .trailer)
        let remote = [MediaURL(url: "https://www.youtube.com/watch?v=abc")]
        #expect(Trailer.choose(local: [local], remote: remote, opensLinks: true) == .local(local))
        #expect(Trailer.choose(local: [], remote: remote, opensLinks: true) == .remote(URL(string: "https://www.youtube.com/watch?v=abc")!))
        // The TV: only one in the library plays.
        #expect(Trailer.choose(local: [], remote: remote, opensLinks: false) == nil)
        #expect(Trailer.choose(local: [local], remote: nil, opensLinks: false) == .local(local))
        // Not a web link, or not playable: no trailer.
        #expect(Trailer.choose(local: [BaseItem(id: "x", name: nil, kind: .folder)], remote: [MediaURL(url: "plugin://x"), MediaURL(url: nil)], opensLinks: true) == nil)
    }

    @Test func extrasLeaveOutThemesAndTrailers() {
        func extra(_ id: String, _ type: String?, minutes: Int? = nil) -> BaseItem {
            var x = BaseItem(id: id, name: id, kind: .video)
            x.extraType = type
            x.runTimeTicks = minutes.map { Int64($0) * 60 * BaseItem.ticksPerSecond }
            return x
        }
        let shown = Extras.shown([extra("a", "BehindTheScenes"), extra("b", "ThemeVideo"), extra("c", "Trailer"), extra("d", nil)])
        #expect(shown.map(\.id) == ["a", "d"])
        #expect(Extras.caption(extra("a", "BehindTheScenes", minutes: 14)) == "Behind the Scenes · 14 min")
        #expect(Extras.caption(extra("b", "DeletedScene")) == "Deleted Scene")
        #expect(Extras.caption(extra("c", nil)) == nil)
    }
}
