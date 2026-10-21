public import Foundation
public import JellyfinAPI

/// How long something stays in Continue Watching after it was last played.
/// Jellyfin keeps a resume point forever; past this, Bumper stops showing
/// it (the point is kept, so it still resumes from its page).
public enum ContinueWatchingWindow: String, Codable, Sendable, CaseIterable, Identifiable {
    case week, month, forever
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .week: "A Week"
        case .month: "A Month"
        case .forever: "Forever"
        }
    }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .forever: nil
        }
    }
}

/// The account's choices, carried to wherever Continue Watching is built.
public struct ContinueWatchingFilter: Sendable, Equatable {
    public var removed: [String: Date]
    public var window: ContinueWatchingWindow
    public init(removed: [String: Date] = [:], window: ContinueWatchingWindow = .forever) {
        self.removed = removed
        self.window = window
    }
    public func apply(_ items: [BaseItem], now: Date = .now) -> [BaseItem] {
        ContinueWatching.keep(items, removed: removed, window: window, now: now)
    }
}

/// What Continue Watching leaves out: things not played within the window,
/// and things the user removed (until they're played again).
public enum ContinueWatching {
    /// `removed`: item id → when it was removed.
    public static func keep(_ items: [BaseItem], removed: [String: Date], window: ContinueWatchingWindow, now: Date = .now) -> [BaseItem] {
        let cutoff = window.days.map { now.addingTimeInterval(-Double($0) * 86_400) }
        return items.filter { item in
            let played = item.userData?.lastPlayedDate
            if let at = removed[item.id], (played ?? .distantPast) <= at { return false }
            if let cutoff, let played, played < cutoff { return false }
            return true
        }
    }

    /// Two devices' removals together: the later time for each item, and
    /// nothing older than a year (it's been played since, or never will be).
    public static func merge(_ a: [String: Date], _ b: [String: Date], now: Date = .now) -> [String: Date] {
        let oldest = now.addingTimeInterval(-365 * 86_400)
        return a.merging(b, uniquingKeysWith: max).filter { $0.value > oldest }
    }

    /// As the server keeps it: one string (seconds since 1970 per id).
    public static func encode(_ removed: [String: Date]) -> String {
        let data = (try? JSONEncoder().encode(removed.mapValues(\.timeIntervalSince1970))) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func decode(_ json: String?) -> [String: Date] {
        guard let data = json?.data(using: .utf8), let raw = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return raw.mapValues(Date.init(timeIntervalSince1970:))
    }
}
