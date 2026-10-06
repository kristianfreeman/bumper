public import JellyfinAPI

/// Which libraries get a tab of their own.
///
/// tvOS's sidebar (`.sidebarAdaptable`) stops opening from the content once
/// it has more than seven entries — on tvOS 26.6 hardware the panel starts to
/// grow and snaps shut (measured: 7 entries open, 8 don't). With Home, Search
/// and Settings fixed, that leaves four library tabs, so libraries fold:
/// - every *books* library becomes one Audiobooks tab (none if they hold no
///   audiobooks — e-book libraries can't play);
/// - *Collections* (box sets) become a row on the Movies page;
/// - past four, the rest go behind a "More" tab.
public struct SidebarPlan: Sendable, Equatable {
    public enum Entry: Sendable, Equatable {
        case library(BaseItem)
        /// All books libraries with audiobooks, as one tab.
        case audiobooks([BaseItem])
        /// Libraries that didn't fit.
        case more([BaseItem])
    }

    public static let maxLibraryTabs = 4
    public var entries: [Entry]
    /// Folded into the Movies page as a row.
    public var collections: [BaseItem]

    public static let supported: Set<String> = ["movies", "tvshows", "boxsets", "homevideos", "musicvideos", "books"]

    /// `views`: the server's libraries, in its order. `hasAudiobooks`: which
    /// books libraries hold any (the rest are e-books).
    /// - Parameter maxTabs: library tabs at most (an iPhone's tab bar has
    ///   room for fewer).
    public init(views: [BaseItem], maxTabs: Int = SidebarPlan.maxLibraryTabs, hasAudiobooks: (BaseItem) -> Bool) {
        let shown = views.filter { $0.collectionType == nil || Self.supported.contains($0.collectionType!) }
        let books = shown.filter { $0.collectionType == "books" && hasAudiobooks($0) }
        let hasMovies = shown.contains { $0.collectionType == "movies" }
        collections = hasMovies ? shown.filter { $0.collectionType == "boxsets" } : []

        var tabs: [Entry] = []
        var addedBooks = false
        for view in shown {
            switch view.collectionType {
            case "books":
                if !books.isEmpty, !addedBooks { tabs.append(.audiobooks(books)); addedBooks = true }
            case "boxsets" where hasMovies:
                continue
            default:
                tabs.append(.library(view))
            }
        }
        if tabs.count > maxTabs {
            let overflow = tabs[(maxTabs - 1)...].flatMap { entry -> [BaseItem] in
                switch entry {
                case .library(let v): [v]
                case .audiobooks(let vs): vs
                case .more(let vs): vs
                }
            }
            tabs = Array(tabs.prefix(maxTabs - 1)) + [.more(overflow)]
        }
        entries = tabs
    }
}
