import JellyfinAPI
import Testing
@testable import AppFeatures

/// The line under a row's title: how many and two you'd know, then when
/// they're from or what you haven't seen — only what stands out.
private func film(_ name: String, _ year: Int?, rating: Double? = nil, seen: Bool = false, kind: ItemKind = .movie) -> BaseItem {
    var i = BaseItem(id: name, name: name, kind: kind)
    i.productionYear = year
    i.communityRating = rating
    i.userData = UserItemData(played: seen)
    return i
}

@Suite("Row lines")
struct RowLineTests {
    /// Mostly the 90s, with Heat and Prisoners the best rated.
    static let thrillers = [
        film("Prisoners", 2013, rating: 8.1), film("Heat", 1995, rating: 8.3), film("Se7en", 1995, rating: 7.9),
        film("Fargo", 1996, rating: 7.6), film("The Fugitive", 1993), film("Copycat", 1995, rating: 6.6),
        film("Sicario", 2015, rating: 7.6), film("Ronin", 1998),
    ]

    @Test func aGenreSaysHowManyTwoYoudKnowAndWhenTheyreFrom() {
        #expect(RowLine.make(.genre, items: Self.thrillers, total: 142) == "142 films, from Heat to Prisoners · mostly the 90s")
    }

    @Test func spreadOutItSaysNoMore() {
        let spread = [film("A", 1962, rating: 7), film("B", 1975, rating: 8), film("C", 1988), film("D", 1994),
                      film("E", 2003), film("F", 2011), film("G", 2021)]
        #expect(RowLine.make(.genre, items: spread, total: 40) == "40 films, from A to B")
    }

    @Test func onlyShortPlainNamesAreNamed() {
        let films = [film("Star Wars: Episode IV – A New Hope", 1977, rating: 9.9), film("Dr. Strangelove", 1964, rating: 9.8),
                     film("The Lord of the Rings", 2001, rating: 9.7), film("Léon", 1994, rating: 8.5),
                     film("Alien 3", 1992, rating: 6.4), film("Up", 2009, rating: 8.3)]
        #expect(RowLine.anchors(films)! == ("Léon", "Up"))
        #expect(RowLine.plain("Blade Runner") && RowLine.plain("Alien 3"))
        #expect(!RowLine.plain("Schindler's List") && !RowLine.plain("Mission Impossible Fallout Again"))
        #expect(RowLine.make(.genre, items: Array(films[0..<3]), total: 3) == "3 films")
    }

    @Test func aDecadeDoesntSayWhenAgain() {
        #expect(RowLine.make(.decade, items: Self.thrillers, total: 61) == "61 films, from Heat to Prisoners")
    }

    @Test func aCollectionSaysItsYearsAndWhatsLeft() {
        let alien = [film("Alien", 1979, seen: true), film("Aliens", 1986, seen: true), film("Alien³", 1992),
                     film("Prometheus", 2012, seen: true), film("Alien: Covenant", 2017)]
        #expect(RowLine.make(.collection, items: alien, total: nil) == "5 films, 1979 to 2017 · 2 you haven't seen")
        #expect(RowLine.make(.collection, items: [film("A", 2001, seen: true), film("B", 2001, seen: true)], total: nil)
                == "2 films, all from 2001 · you've seen both")
    }

    @Test func showsAreShows() {
        let shows = [film("The Wire", 2002, rating: 9.3, kind: .series), film("Lost", 2004, rating: 8.3, kind: .series)]
        #expect(RowLine.make(.genre, items: shows, total: 9) == "9 shows, from The Wire to Lost")
    }

    @Test func littleToGoOnStillSaysSomethingOrNothing() {
        #expect(RowLine.make(.genre, items: [film("A", nil)], total: 1) == "1 film")
        #expect(RowLine.make(.genre, items: [film("A", nil)], total: nil) == nil)
        #expect(RowLine.make(.genre, items: [], total: 4) == nil)
    }
}
