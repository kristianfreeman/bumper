import AppCore
import Foundation
import Instrumentation
import JellyfinAPI
import PlaybackCore

/// At the credits: what now.
struct EndCard: Equatable {
    /// How long Keep Going waits before it goes on by itself.
    static let seconds = 8
    /// What Keep Going plays (`upNext`); nil: nothing's next.
    let next: BaseItem?
    /// Seconds left before it does.
    var countdown: Int
    /// Something different: like this, not from this show.
    let instead: BaseItem?
    /// Up over the credits as they roll (else over the last frame).
    let atCredits: Bool
}

/// Up Next on the watch page: what plays after this one, and adding to it.
extension PlayerController {
    /// What plays after this one, in order, as `finishedItem()` will go: a
    /// playlist's rest; the queue after this one; else, with Play Next
    /// Episode on, the next episode (and the show goes on from there).
    var upNextList: [BaseItem] {
        if !request.sequence.isEmpty { return request.sequence }
        if isBackground { return nextEpisode.map { [$0] } ?? [] }
        var list: [BaseItem] = []
        let entries = app.queue.plan.entries
        if let i = entries.firstIndex(where: { $0.id == item.id }) { list = entries.dropFirst(i + 1).map(\.item) }
        if list.isEmpty, app.settings.autoplayNextEpisode, let next = nextEpisode { list = [next] }
        return list
    }

    /// Added by the queue's suggestions, not by you.
    func isSuggested(_ id: String) -> Bool { app.queue.plan.entries.first { $0.id == id }?.ambient == true }

    /// A playlist and Background run their own course: nothing to add to.
    var canAddToUpNext: Bool { request.sequence.isEmpty && !isBackground }

    func isUpNext(_ id: String) -> Bool { upNextList.contains { $0.id == id } }

    /// Plays next by itself (the next episode, not queued): it can't be taken out here.
    func isAutomatic(_ id: String) -> Bool { isUpNext(id) && !app.queue.contains(id) }

    /// Onto the end of Up Next. Not queued yet: what Up Next shows becomes
    /// the queue first (this one, then its next episode), so the list keeps
    /// its order and the new one plays after it.
    func addToUpNext(_ added: BaseItem) {
        guard canAddToUpNext, !app.queue.contains(added.id), added.id != item.id else { return }
        if !app.queue.contains(item.id) {
            let shown = upNextList
            app.queue.insert(item, at: 0)
            for (i, next) in shown.enumerated() { app.queue.insert(next, at: i + 1) }
        }
        app.queue.add(added)
    }

    func removeFromUpNext(_ id: String) { app.queue.remove(id) }

    /// The + / ✓ in Add to Up Next.
    func toggleUpNext(_ other: BaseItem) {
        if app.queue.contains(other.id) { removeFromUpNext(other.id) } else { addToUpNext(other) }
    }

    /// The end card's other choice: like this, from another show (or a film), not already next.
    var somethingDifferent: BaseItem? {
        let next = Set(upNextList.prefix(1).map(\.id))
        return similarItems.first { !next.contains($0.id) && $0.id != item.id }
    }

    /// Add to Up Next: the rest of the show, things like it, and what's next in your other shows.
    var addSections: [(title: String, items: [BaseItem])] {
        var sections: [(String, [BaseItem])] = []
        let show = item.seriesId
        let more = followingEpisodes.filter { !isAutomatic($0.id) }
        if !more.isEmpty { sections.append(("More from \(item.seriesName ?? "the show")", Array(more.prefix(8)))) }
        if !similarItems.isEmpty { sections.append(("Like This", Array(similarItems.prefix(8)))) }
        let others = app.queue.candidates.filter { $0.seriesId != show && $0.id != item.id }
        if !others.isEmpty { sections.append(("Next in Your Shows", Array(others.prefix(6)))) }
        return sections
    }

    /// When each of `upNextList` ends, back to back from the end of this one.
    func upNextEnds(now: Date = .now) -> [Date] {
        let left = engine.map { max(.zero, ($0.duration ?? item.runtime ?? .zero) - $0.currentTime) } ?? item.runtime ?? .zero
        var t = now.addingTimeInterval(left.seconds)
        return upNextList.map { next in
            t = t.addingTimeInterval(QueuePlan.remaining(next))
            return t
        }
    }
}
