@testable import AppCore
import Foundation
import JellyfinAPI
import Testing

/// The written copy reads like a sentence for the situation it's given.
@Suite("Editorial copy")
struct EditorialTests {
    static let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    static func date(_ hour: Int, day: Int = 7) -> Date {   // 2026-10-07, a Wednesday
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    static func item(_ name: String, minutesLeft: Int? = nil, addedDaysAgo: Double? = nil, series: String? = nil, now: Date) -> BaseItem {
        var i = BaseItem(id: name, name: name, kind: series == nil ? .movie : .episode)
        i.seriesName = series
        i.runTimeTicks = 60 * 60 * BaseItem.ticksPerSecond
        if let m = minutesLeft {
            var d = UserItemData()
            d.playbackPositionTicks = Int64(60 - m) * 60 * BaseItem.ticksPerSecond
            i.userData = d
        }
        i.dateCreated = addedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
        return i
    }

    @Test func writesForTheMoment() {
        let evening = Self.date(20)
        let e = Editorial(now: evening, calendar: Self.calendar, userName: "Sam Rivera",
                          inProgress: [Self.item("The Top Ten", minutesLeft: 22, series: "Ancient Aliens", now: evening), Self.item("Baraka", minutesLeft: 50, now: evening)],
                          nextUp: [Self.item("e1", series: "Lost", now: evening)],
                          recentMovies: [Self.item("A", addedDaysAgo: 1, now: evening), Self.item("B", addedDaysAgo: 3, now: evening), Self.item("C", addedDaysAgo: 30, now: evening)],
                          recentShows: [Self.item("S", addedDaysAgo: 2, now: evening)])
        #expect(e.greeting.hasSuffix(", Sam."))
        #expect(e.lede == "You're 22 minutes from the end of Ancient Aliens. Two films and one show arrived this week.")
        #expect(e.resume.subtitle == "Two things on the go — about an hour and a quarter left between them.")
        #expect(e.recent(e.recentMovies, library: "Movies").title == "New this week")
        #expect(e.upNext.subtitle == "New episodes of Lost.")

        #expect(Editorial(now: evening, calendar: Self.calendar, userName: "sam").greeting.hasSuffix(", Sam."))
        let late = Editorial(now: Self.date(1), calendar: Self.calendar, userName: nil)
        #expect(["Up late", "Still up", "Burning"].contains { late.greeting.hasPrefix($0) })
        #expect(late.lede == "Something short before bed?")
    }

    @Test func greetsTheDay() {
        // Friday 2026-10-09 evening; Halloween; a Saturday morning.
        #expect(Editorial(now: Self.date(20, day: 9), calendar: Self.calendar, userName: "sam").greeting == "Friday night, Sam.")
        #expect(Editorial(now: Self.date(20, day: 31), calendar: Self.calendar, userName: nil).greeting == "Happy Halloween.")
        #expect(Editorial(now: Self.date(9, day: 10), calendar: Self.calendar, userName: nil).greeting == "A slow Saturday morning.")
    }

    @Test func saysWhen() {
        let now = Self.date(20)
        let e = Editorial(now: now, calendar: Self.calendar, userName: nil)
        #expect(e.when(now) == "today")
        #expect(e.when(now.addingTimeInterval(-86_400)) == "yesterday")
        #expect(e.when(now.addingTimeInterval(-3 * 86_400)) == "on Sunday")
        #expect(e.when(now.addingTimeInterval(-21 * 86_400)) == "three weeks ago")
    }

    @Test func libraryAndCollectionLines() {
        let now = Self.date(20)
        var newest = Self.item("Severance", addedDaysAgo: 1, now: now)
        newest.communityRating = 8.7
        #expect(LibraryWords.lede(all: 48, unwatched: 36, noun: ("show", "shows"), newest: nil, isShows: true) == "48 shows, 36 with episodes you haven't seen.")
        #expect(LibraryWords.subtitle("top", total: 30, noun: ("show", "shows"), first: newest, minRating: 7.5, now: now) == "Rated 7.5 and up; Severance leads at 8.7.")
        #expect(LibraryWords.genre("Comedy", count: 23, noun: ("show", "shows")) == "23 comedy shows, for when you need a laugh.")

        var filter = CollectionFilter(base: ItemQuery(includeItemTypes: [.series]), libraryName: "Shows")
        filter.added = .month
        #expect(CollectionWords.lede(title: "New", filter: filter, total: 9, items: [newest], fixed: false, now: now) == "Nine shows arrived in the last month — the newest is Severance.")
    }
}
