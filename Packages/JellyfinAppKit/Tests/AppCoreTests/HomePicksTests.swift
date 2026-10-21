@testable import AppCore
import Foundation
import JellyfinAPI
import Testing

/// Home's pick: the likeliest thing first, with a reason that says why.
@Suite("Home picks")
struct HomePicksTests {
    static let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    static func date(_ hour: Int) -> Date {   // 2026-10-07, a Wednesday
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: hour))!
    }
    static func item(_ id: String, minutes: Int = 60, left: Int? = nil, series: String? = nil, addedDaysAgo: Double? = nil, now: Date = date(20)) -> BaseItem {
        var i = BaseItem(id: id, name: id, kind: series == nil ? .movie : .episode)
        i.seriesId = series
        i.seriesName = series
        i.runTimeTicks = Int64(minutes) * 60 * BaseItem.ticksPerSecond
        if let left {
            var d = UserItemData()
            d.playbackPositionTicks = Int64(minutes - left) * 60 * BaseItem.ticksPerSecond
            i.userData = d
        }
        i.dateCreated = addedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
        return i
    }

    @Test func ranksTheQueueThenWhatsNearlyDoneThenTheNextEpisode() {
        let picks = HomePicks.make(now: Self.date(20), calendar: Self.calendar,
                                   queue: [Self.item("Queued")],
                                   inProgress: [Self.item("Long", minutes: 120, left: 75), Self.item("Nearly", minutes: 52, left: 12, series: "Paper Moons")],
                                   nextUp: [Self.item("Next", minutes: 28, series: "Northern Line")],
                                   newMovies: [Self.item("Fresh", addedDaysAgo: 1), Self.item("Old", addedDaysAgo: 40)])
        #expect(picks.map(\.item.id) == ["Queued", "Nearly", "Next", "Long", "Fresh"])
        #expect(picks.map(\.reason) == ["Next in your queue", "12 minutes left", "Next episode", "About an hour and a quarter left", "Arrived yesterday"])
    }

    @Test func oneEpisodePerShowAndOnlyWhatPlays() {
        let show = BaseItem(id: "Show", name: "Show", kind: .series)
        let picks = HomePicks.make(now: Self.date(20), calendar: Self.calendar,
                                   queue: [show],
                                   inProgress: [Self.item("E4", minutes: 50, left: 20, series: "Glasshouse")],
                                   nextUp: [Self.item("E5", series: "Glasshouse"), Self.item("Other", series: "Small Hours")])
        #expect(picks.map(\.item.id) == ["E4", "Other"])
    }

    @Test func aStartedNextEpisodeSaysWhatsLeft() {
        let picks = HomePicks.make(now: Self.date(20), calendar: Self.calendar, nextUp: [Self.item("E3", minutes: 43, left: 25, series: "Station")])
        #expect(picks.first?.reason == "25 minutes left")
        #expect(picks.first?.minutesLeft == 25 && picks.first?.reasonIsTimeLeft == true)    // Resume says it instead
    }

    @Test func shortThingsFirstLateAtNight() {
        func picks(at hour: Int) -> [String] {
            HomePicks.make(now: Self.date(hour), calendar: Self.calendar,
                           queue: [Self.item("Film", minutes: 120)],
                           nextUp: [Self.item("Half hour", minutes: 24, series: "Small Hours")]).map(\.item.id)
        }
        #expect(picks(at: 20) == ["Film", "Half hour"])
        #expect(picks(at: 1) == ["Half hour", "Film"])
    }

    @Test func stopsAtTheLimit() {
        let many = (0..<(HomePicks.limit + 4)).map { Self.item("Film \($0)", addedDaysAgo: 2) }
        #expect(HomePicks.make(now: Self.date(20), calendar: Self.calendar, newMovies: many).count == HomePicks.limit)
        #expect(HomePicks.make(now: Self.date(20), calendar: Self.calendar).isEmpty)
    }
}
