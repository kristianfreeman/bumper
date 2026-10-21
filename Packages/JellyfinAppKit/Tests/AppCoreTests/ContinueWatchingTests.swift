import Foundation
import JellyfinAPI
import Testing
@testable import AppCore

/// Continue Watching keeps what's been played lately, leaves out what was
/// removed, and takes it back once it's played again.
struct ContinueWatchingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    func item(_ id: String, played: Date) -> BaseItem {
        var item = BaseItem(id: id, name: id, kind: .episode)
        item.userData = UserItemData(playbackPositionTicks: 1)
        item.userData?.lastPlayedDate = played
        return item
    }

    @Test func oldThingsLeaveRemovedOnesStayGoneUntilPlayedAgain() {
        let items = [item("fresh", played: day(2)), item("stale", played: day(20)), item("removed", played: day(3)), item("again", played: day(1))]
        let removed = ["removed": day(2), "again": day(2)]
        let week = ContinueWatching.keep(items, removed: removed, window: .week, now: now).map(\.id)
        #expect(week == ["fresh", "again"])
        let forever = ContinueWatching.keep(items, removed: removed, window: .forever, now: now).map(\.id)
        #expect(forever == ["fresh", "stale", "again"])
    }

    @Test func twoDevicesRemovalsMergeAndSurviveTheServer() {
        let merged = ContinueWatching.merge(["a": day(5), "b": day(400)], ["a": day(1), "c": day(2)], now: now)
        #expect(merged == ["a": day(1), "c": day(2)])
        #expect(ContinueWatching.decode(ContinueWatching.encode(merged)) == merged)
    }
}
