@testable import AppCore
import Foundation
import JellyfinAPI
import Testing

/// Words become filters; filters become a sentence and a query.
@Suite("Collection filter")
struct CollectionFilterTests {
    @Test func readsARequestAndWritesItBack() {
        var f = CollectionFilter(base: ItemQuery(parentId: "movies", includeItemTypes: [.movie]), libraryName: "Movies")
        let changed = f.apply(words: "Something funny from the 80s I haven't seen, under an hour and a half", genres: ["Action", "Comedy", "Drama"])
        #expect(Set(changed) == [.watched, .decade, .length, .genre])
        #expect(f.sentence == "Movies · unwatched · comedy · from the 1980s · under 90 minutes")
        let q = f.query
        #expect(q.filters == ["IsUnplayed"] && q.genres == ["Comedy"] && q.years == Array(1980...1989))

        var recent = CollectionFilter(base: ItemQuery(parentId: "shows"), libraryName: "Shows")
        recent.apply(words: "best new stuff this week")
        #expect(recent.added == .week && recent.minRating == 7.5)
        #expect(recent.query.sortBy.first == "DateCreated")           // newest first, to stop at the cutoff
        var old = BaseItem(id: "x", name: "x", kind: .series)
        old.dateCreated = .now.addingTimeInterval(-10 * 86_400)
        #expect(!recent.matches(old))
        recent.clear(.added)
        #expect(recent.matches(old) && recent.sentence == "Shows · rated 7.5+")
    }
}
