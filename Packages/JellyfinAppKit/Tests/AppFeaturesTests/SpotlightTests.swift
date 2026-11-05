import JellyfinAPI
import Testing
@testable import AppFeatures

/// Every few rows, one film from the row below the whole width: where they
/// go, which film, and the line about it.
@Suite("Spotlight")
struct SpotlightTests {
    static func row(_ id: String) -> BrowseSection {
        Shelves.shelf(id, id, subtitle: nil, ItemQuery(includeItemTypes: [.movie], limit: 24))
    }

    @Test func afterTheFirstFewThenEveryFifthEachOverItsRow() {
        let rows = (0..<14).map { Self.row("r\($0)") }
        let page = Spotlight.placed(in: rows)
        let spots = page.enumerated().filter { $0.element.spotlight != nil }
        #expect(spots.map(\.element.spotlight) == ["r3", "r8", "r13"])
        // Each sits right above the row it's from, with its name.
        for (i, spot) in spots { #expect(page[i + 1].id == spot.spotlight && spot.title == page[i + 1].title) }
        // A row with no query behind it (Because You Watched's Similar) gets none.
        var similar = Self.row("r3")
        similar.source = .similar("x")
        #expect(Spotlight.placed(in: Array(rows[0..<3]) + [similar]).allSatisfy { $0.spotlight == nil })
    }

    static func film(_ name: String, rating: Double?, seen: Bool = false, started: Bool = false, backdrop: Bool = true, kind: ItemKind = .movie) -> BaseItem {
        var i = BaseItem(id: name, name: name, kind: kind)
        i.communityRating = rating
        i.userData = UserItemData(playbackPositionTicks: started ? 600_000_000 : nil, played: seen)
        if backdrop { i.backdropImageTags = ["b"] }
        return i
    }

    @Test func theBestRatedYouHaventSeenOrStartedWithAPicture() {
        let items = [Self.film("Seen", rating: 9.5, seen: true), Self.film("Started", rating: 9.4, started: true),
                     Self.film("NoPicture", rating: 9.3, backdrop: false), Self.film("Episode", rating: 9.2, kind: .episode),
                     Self.film("Good", rating: 7.1), Self.film("Best", rating: 8.4), Self.film("Unrated", rating: nil)]
        #expect(Spotlight.candidates(items, excluding: []).map(\.id) == ["Best", "Good", "Unrated"])
        // One spotlight a film: the next one along takes the next best.
        #expect(Spotlight.candidates(items, excluding: ["Best"]).first?.id == "Good")
    }

    @Test func aLineOfWhatItsAbout() {
        #expect(Spotlight.blurb("A boy grows up in Miami, in three chapters of his life. Each one is a different age.")
                == "A boy grows up in Miami, in three chapters of his life.")
        // A very short first sentence takes the next with it.
        #expect(Spotlight.blurb("A thief. He takes one last job in Los Angeles. The police close in.")
                == "A thief. He takes one last job in Los Angeles.")
        // Initials and titles aren't the end of a sentence.
        #expect(Spotlight.blurb("Dr. Strange and the U.S. army meet in New York for the first time. Then more.")
                == "Dr. Strange and the U.S. army meet in New York for the first time.")
        #expect(Spotlight.blurb("No full stop at all") == "No full stop at all")
    }
}
