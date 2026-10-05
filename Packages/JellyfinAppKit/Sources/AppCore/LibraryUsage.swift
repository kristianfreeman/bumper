public import Foundation
public import JellyfinAPI

/// How much each library gets used, so the sidebar, Home and the Top Shelf
/// put the ones you live in first. Opening a library counts once, playing
/// something from it three times; older use fades (each new use scales the
/// rest down a little), so the order follows what you watch now.
@MainActor
public final class LibraryUsage {
    private let defaults: UserDefaults
    private let key = "libraries.usage"
    public private(set) var scores: [String: Double]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scores = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    public static let openWeight = 1.0
    public static let playWeight = 3.0
    /// Per use: everything else keeps 98% (about a 35-use half-life).
    public static let decay = 0.98

    public func record(_ libraryId: String, weight: Double) {
        for (id, score) in scores { scores[id] = score * Self.decay }
        scores[libraryId, default: 0] += weight
        defaults.set(scores, forKey: key)
    }

    /// Something played: credit the library it most likely came from (the
    /// first one of the matching kind).
    public func recordPlay(_ item: BaseItem, libraries: [BaseItem]) {
        let type: String? = switch item.kind {
        case .movie: "movies"
        case .episode, .series, .season: "tvshows"
        case .audioBook: "books"
        case .musicVideo: "musicvideos"
        case .audio: "music"
        default: nil
        }
        guard let type, let library = libraries.first(where: { $0.collectionType == type }) else { return }
        record(library.id, weight: Self.playWeight)
    }

    public func ordered(_ views: [BaseItem]) -> [BaseItem] { LibraryOrder.ordered(views, scores: scores) }
}

public enum LibraryOrder {
    /// With no history yet: films and shows before everything else.
    static let prior: [String: Int] = ["movies": 0, "tvshows": 1, "boxsets": 2, "homevideos": 3, "musicvideos": 4, "music": 5, "books": 6, "playlists": 7]

    /// Most used first; ties (and no history at all) by kind, then the
    /// server's own order.
    public static func ordered(_ views: [BaseItem], scores: [String: Double]) -> [BaseItem] {
        views.enumerated().sorted { a, b in
            let sa = scores[a.element.id] ?? 0, sb = scores[b.element.id] ?? 0
            if abs(sa - sb) > 0.01 { return sa > sb }
            let pa = prior[a.element.collectionType ?? ""] ?? 8, pb = prior[b.element.collectionType ?? ""] ?? 8
            if pa != pb { return pa < pb }
            return a.offset < b.offset
        }
        .map(\.element)
    }
}
