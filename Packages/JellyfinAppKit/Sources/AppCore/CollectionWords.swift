public import Foundation
public import JellyfinAPI

/// The line under a collection page's title: what's here, said the way the
/// rest of the app says things — "Nine shows arrived in the last month; the
/// newest is Severance." rather than "140 titles."
public enum CollectionWords {
    /// - Parameters:
    ///   - total: how many there are (nil while loading, or when the page
    ///     can't know — filtered on the device).
    ///   - items: what's loaded so far (newest/highest first where sorted so).
    ///   - fixed: a Home row's whole list (Continue Watching, Next Up).
    public static func lede(title: String, filter: CollectionFilter, total: Int?, items: [BaseItem], fixed: Bool, now: Date = .now) -> String? {
        let words = Editorial(now: now, userName: nil)
        guard !items.isEmpty else { return nil }
        let n = total ?? items.count
        let exact = total != nil
        let noun = Self.noun(filter: filter, items: items)
        let count = exact ? "\(words.number(n)) \(n == 1 ? noun.one : noun.many)" : "\(noun.many.capitalizedFirst) so far"
        func named(_ item: BaseItem?) -> String? { item.flatMap { $0.seriesName ?? $0.name } }

        if fixed {
            let left = items.compactMap(minutesLeft).reduce(0, +)
            if left > 0 {
                return "\(words.number(items.count).capitalizedFirst) things in progress, \(words.roughly(left)) left between them."
            }
            let shows = Set(items.compactMap(\.seriesName))
            if shows.count > 1 {
                return "\(words.number(items.count).capitalizedFirst) episodes waiting, across \(words.number(shows.count)) shows. \(named(items.first).map { "First up: \($0)." } ?? "")"
                    .trimmingCharacters(in: .whitespaces)
            }
            return "\(count.capitalizedFirst)."
        }

        var line: String
        switch true {
        case filter.added != .any:
            let when = switch filter.added { case .week: "this week"; case .month: "in the last month"; default: "this year" }
            line = exact ? "\(count.capitalizedFirst) arrived \(when)" : "New \(when)"
            if let newest = named(items.first) { line += exact ? " — the newest is \(newest)." : ", starting with \(newest)." } else { line += "." }
        case filter.minRating != nil:
            line = "\(count.capitalizedFirst) rated \(rating(filter.minRating!)) or higher"
            if let best = items.first, let name = named(best), let score = best.communityRating {
                line += ". At the top: \(name), at \(rating(score))."
            } else { line += "." }
        case filter.decade != nil:
            line = "\(count.capitalizedFirst) from the \(filter.decade!)s"
            line += filter.sort == .released ? ", newest first." : "."
        case filter.watched == .unwatched:
            line = "\(count.capitalizedFirst) you haven't seen"
            line += named(items.first).map { ". \($0) is as good a place to start as any." } ?? "."
        case filter.favourites:
            line = n == 1 ? "Just the one favourite so far." : "The \(words.number(n)) you've starred."
        case filter.genre != nil:
            line = "\(count.capitalizedFirst) filed under \(filter.genre!.lowercased())."
        case filter.sort == .added:
            line = "\(count.capitalizedFirst), newest first" + (named(items.first).map { " — most recently \($0)." } ?? ".")
        case filter.sort == .rating:
            line = "\(count.capitalizedFirst), best rated first."
        case filter.sort == .released:
            line = "\(count.capitalizedFirst), latest premieres first."
        default:
            line = "\(count.capitalizedFirst), A to Z."
        }
        return line
    }

    static func noun(filter: CollectionFilter, items: [BaseItem]) -> (one: String, many: String) {
        let kinds = Set(filter.base.includeItemTypes.isEmpty ? items.map(\.kind) : filter.base.includeItemTypes)
        if kinds == [.series] { return ("show", "shows") }
        if kinds == [.movie] { return ("film", "films") }
        if kinds == [.episode] { return ("episode", "episodes") }
        if kinds == [.boxSet] { return ("collection", "collections") }
        return ("title", "titles")
    }

    static func rating(_ r: Double) -> String { r.formatted(.number.precision(.fractionLength(0...1))) }

    static func minutesLeft(_ item: BaseItem) -> Int? {
        guard let total = item.runTimeTicks, let pos = item.userData?.playbackPositionTicks, total > pos, pos > 0 else { return nil }
        return Int(Double(total - pos) / Double(BaseItem.ticksPerSecond) / 60)
    }
}
