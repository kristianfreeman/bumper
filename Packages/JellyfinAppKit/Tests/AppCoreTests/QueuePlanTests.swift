@testable import AppCore
import Foundation
import JellyfinAPI
import Testing

/// Queue's times add up; suggestions fit before "done by"; finishing moves on.
@Suite("Queue")
struct QueuePlanTests {
    static func item(_ id: String, minutes: Int, watched: Int = 0) -> BaseItem {
        var i = BaseItem(id: id, name: id, kind: .movie)
        i.runTimeTicks = Int64(minutes) * 60 * BaseItem.ticksPerSecond
        var d = UserItemData()
        d.playbackPositionTicks = Int64(watched) * 60 * BaseItem.ticksPerSecond
        i.userData = d
        return i
    }

    @Test func plansTheEvening() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var plan = QueuePlan()
        plan.add(Self.item("film", minutes: 120, watched: 30))           // 90 left
        plan.add(Self.item("episode", minutes: 45))
        plan.doneBy = now.addingTimeInterval(3 * 3600)                     // 180 min
        plan.suggest([Self.item("next1", minutes: 40), Self.item("next2", minutes: 40)], now: now)
        // 90 + 45 = 135; one 40-min suggestion fits (175), the second wouldn't (215).
        #expect(plan.entries.map(\.id) == ["film", "episode", "next1"])
        let slots = plan.timeline(now: now)
        #expect(slots.map { Int($0.start.timeIntervalSince(now) / 60) } == [0, 90, 135])
        #expect(slots.allSatisfy { !$0.overruns })

        plan.add(Self.item("late", minutes: 60))                         // picks go before suggestions
        #expect(plan.entries.map(\.id) == ["film", "episode", "late", "next1"])
        #expect(plan.timeline(now: now).first { $0.entry.id == "next1" }?.overruns == true)
        #expect(plan.next(after: "film")?.id == "episode")
        plan.finished("episode")
        #expect(plan.entries.map(\.id) == ["late", "next1"])
    }
}
