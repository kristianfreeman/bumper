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
        let e = Editorial(now: evening, calendar: Self.calendar, userName: "Kristian Freeman",
                          inProgress: [Self.item("The Top Ten", minutesLeft: 22, series: "Ancient Aliens", now: evening), Self.item("Baraka", minutesLeft: 50, now: evening)],
                          nextUp: [Self.item("e1", series: "Lost", now: evening)],
                          recentMovies: [Self.item("A", addedDaysAgo: 1, now: evening), Self.item("B", addedDaysAgo: 3, now: evening), Self.item("C", addedDaysAgo: 30, now: evening)],
                          recentShows: [Self.item("S", addedDaysAgo: 2, now: evening)])
        #expect(e.greeting.hasSuffix(", Kristian."))
        #expect(e.lede == "You're 22 minutes from the end of Ancient Aliens. Two films and one show arrived this week.")
        #expect(e.resume.subtitle == "Two things in progress — about an hour and a quarter in all.")
        #expect(e.recent(e.recentMovies, library: "Movies").title == "New this week")
        #expect(e.upNext.subtitle == "Continuing Lost.")

        #expect(Editorial(now: evening, calendar: Self.calendar, userName: "kristian").greeting.hasSuffix(", Kristian."))
        let late = Editorial(now: Self.date(1), calendar: Self.calendar, userName: nil)
        #expect(late.greeting.hasPrefix("Up late") || late.greeting.hasPrefix("Still up"))
        #expect(late.lede == "Something short before bed?")
    }
}
