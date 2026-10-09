public import Foundation
public import JellyfinAPI

/// Queue: what you mean to watch, in order, with the time each starts and
/// when it all ends — and, optionally, when you want to be done ("done by
/// 11:30"), which is when playback stops. Ambient suggestions (the next
/// episode of something in the plan) fill in after your own picks.
///
/// Pure: the store persists it, the views draw it, tests check the times.
public struct QueuePlan: Sendable, Codable, Equatable {
    public struct Entry: Sendable, Codable, Equatable, Identifiable {
        public var item: BaseItem
        /// A suggestion the plan added, not something you picked.
        public var ambient: Bool
        public var id: String { item.id }

        public init(item: BaseItem, ambient: Bool = false) {
            self.item = item
            self.ambient = ambient
        }
    }

    public struct Slot: Sendable, Equatable {
        public var entry: Entry
        public var start: Date
        public var end: Date
        /// Ends after "done by".
        public var overruns: Bool
    }

    public var entries: [Entry] = []
    public var doneBy: Date?

    public init() {}

    public var picks: [Entry] { entries.filter { !$0.ambient } }
    public func contains(_ id: String) -> Bool { entries.contains { $0.id == id } }

    public mutating func add(_ item: BaseItem) {
        entries.removeAll { $0.id == item.id && $0.ambient }        // a suggestion you pick is yours
        guard !contains(item.id) else { return }
        // Picks go before the suggestions.
        let at = entries.firstIndex(where: \.ambient) ?? entries.count
        entries.insert(Entry(item: item), at: at)
    }

    /// In a place of its own choosing (the watch page puts what's playing,
    /// and what it showed as next, at the front).
    public mutating func insert(_ item: BaseItem, at index: Int) {
        entries.removeAll { $0.id == item.id && $0.ambient }        // a suggestion put in place is yours
        guard !contains(item.id) else { return }
        entries.insert(Entry(item: item), at: max(0, min(index, entries.count)))
    }

    public mutating func remove(_ id: String) { entries.removeAll { $0.id == id } }

    public mutating func move(_ id: String, by offset: Int) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(entries.count - 1, i + offset))
        let e = entries.remove(at: i)
        entries.insert(e, at: j)
    }

    /// Something finished playing: drop it (and anything before it).
    public mutating func finished(_ id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.removeFirst(i + 1)
    }

    /// The entry after `id` (what to play next), else the first one.
    public func next(after id: String?) -> Entry? {
        guard let id, let i = entries.firstIndex(where: { $0.id == id }) else { return entries.first }
        return i + 1 < entries.count ? entries[i + 1] : nil
    }

    /// Replace the suggestions: up to `limit`, not already planned, and only
    /// what fits before "done by" when one is set.
    public mutating func suggest(_ candidates: [BaseItem], limit: Int = 2, now: Date = .now) {
        entries.removeAll(where: \.ambient)
        var end = timeline(now: now).last?.end ?? now
        var added = 0
        for c in candidates where added < limit && !contains(c.id) {
            let length = Self.remaining(c)
            if let doneBy, end.addingTimeInterval(length) > doneBy { break }
            entries.append(Entry(item: c, ambient: true))
            end = end.addingTimeInterval(length)
            added += 1
        }
    }

    /// Start and end of each entry, back to back from `now`.
    public func timeline(now: Date = .now) -> [Slot] {
        var t = now
        return entries.map { e in
            let end = t.addingTimeInterval(Self.remaining(e.item))
            defer { t = end }
            return Slot(entry: e, start: t, end: end, overruns: doneBy.map { end > $0 } ?? false)
        }
    }

    public func endsAt(now: Date = .now) -> Date? { timeline(now: now).last?.end }

    /// Seconds left to watch (from the resume point).
    public static func remaining(_ item: BaseItem) -> TimeInterval {
        let total = Double(item.runTimeTicks ?? 0) / Double(BaseItem.ticksPerSecond)
        let done = Double(item.userData?.playbackPositionTicks ?? 0) / Double(BaseItem.ticksPerSecond)
        return max(0, total - done)
    }
}
