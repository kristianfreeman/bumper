public import Foundation
public import JellyfinAPI

/// What Home leads with: the one thing you'd most likely watch now, and a
/// few others in case it isn't. Each comes with its reason ("12 minutes
/// left", "Next in your queue"), in the app's written voice.
///
/// Only things Play can start (a film, an episode): the pick's first button
/// plays it. Ranked by rules, not a model — your queue, then what you're
/// nearly done with, then the next episode of what you're watching, then the
/// rest of what's started, then this week's films. Late at night the short
/// ones come first. Pure and deterministic, so it's unit-tested.
public struct HomePicks: Sendable {
    public struct Pick: Sendable, Equatable, Identifiable {
        public var item: BaseItem
        public var reason: String
        /// Minutes left, for something already started (Resume says it).
        public var minutesLeft: Int?
        /// The reason is just the time left ("12 minutes left"): where
        /// Resume says it, the reason needn't.
        public var reasonIsTimeLeft = false
        public var id: String { item.id }
        public init(item: BaseItem, reason: String, minutesLeft: Int? = nil, reasonIsTimeLeft: Bool = false) {
            self.item = item
            self.reason = reason
            self.minutesLeft = minutesLeft
            self.reasonIsTimeLeft = reasonIsTimeLeft
        }
        public static func == (a: Self, b: Self) -> Bool { a.item.id == b.item.id && a.reason == b.reason }
    }

    /// The pick and the others after it (the row under it scrolls).
    public static let limit = 10
    /// Nearly done: this little left counts as finishing something.
    static let nearlyDone = 30
    /// Short enough for late at night.
    static let short = 35

    public static func make(now: Date = .now, calendar: Calendar = .current, queue: [BaseItem] = [], inProgress: [BaseItem] = [],
                            nextUp: [BaseItem] = [], newMovies: [BaseItem] = [], limit: Int = Self.limit) -> [Pick] {
        let words = Editorial(now: now, calendar: calendar, userName: nil)
        func left(_ item: BaseItem) -> Int? {
            guard let total = item.runTimeTicks, let pos = item.userData?.playbackPositionTicks, total > pos, pos > 0 else { return nil }
            return Int(Double(total - pos) / Double(BaseItem.ticksPerSecond) / 60)
        }
        func leftReason(_ m: Int) -> String { m < 60 ? "\(words.minutes(max(1, m))) left" : "\(words.roughly(m).capitalizedFirst) left" }
        func resumable(_ item: BaseItem, _ m: Int) -> Pick { Pick(item: item, reason: leftReason(m), minutesLeft: m, reasonIsTimeLeft: true) }
        func runtime(_ item: BaseItem) -> Int? { item.runTimeTicks.map { Int(Double($0) / Double(BaseItem.ticksPerSecond) / 60) } }

        var ranked: [Pick] = []
        if let first = queue.first(where: playable) { ranked.append(Pick(item: first, reason: "Next in your queue", minutesLeft: left(first))) }
        let started = inProgress.filter(playable).compactMap { item in left(item).map { (item, $0) } }
        ranked += started.filter { $0.1 <= nearlyDone }.map { resumable($0.0, $0.1) }
        // A next episode already started says how much is left, like the rest.
        func next(_ item: BaseItem) -> Pick { left(item).map { resumable(item, $0) } ?? Pick(item: item, reason: "Next episode") }
        ranked += nextUp.filter(playable).prefix(2).map(next)
        ranked += started.filter { $0.1 > nearlyDone }.map { resumable($0.0, $0.1) }
        let week = now.addingTimeInterval(-7 * 86_400)
        let arrived = newMovies.filter { playable($0) && !$0.isPlayed && ($0.dateCreated ?? .distantPast) > week }
        ranked += arrived.map { Pick(item: $0, reason: "Arrived \(words.when($0.dateCreated))") }
        ranked += nextUp.filter(playable).dropFirst(2).map(next)
        ranked += queue.filter(playable).dropFirst().map { Pick(item: $0, reason: "In your queue", minutesLeft: left($0)) }

        // One of each thing, and one episode per show (the first to rank).
        var seen = Set<String>()
        var picks = ranked.filter { seen.insert($0.item.id).inserted && seen.insert("series-" + ($0.item.seriesId ?? $0.item.id)).inserted }

        if words.timeOfDay == .late {
            // Before bed: whatever's short first, in the order it ranked.
            func length(_ p: Pick) -> Int { left(p.item) ?? runtime(p.item) ?? .max }
            let shortOnes = picks.filter { length($0) <= short }
            picks = shortOnes + picks.filter { length($0) > short }
        }
        return Array(picks.prefix(limit))
    }

    static func playable(_ item: BaseItem) -> Bool { item.kind == .movie || item.kind == .episode }
}
