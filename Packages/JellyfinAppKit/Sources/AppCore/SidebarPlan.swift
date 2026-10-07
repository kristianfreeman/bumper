public import JellyfinAPI

/// Which libraries get a tab of their own — and, for Settings → Libraries,
/// where every library on the server went and why.
///
/// tvOS's sidebar stopped opening past seven entries, and an iPhone's tab bar
/// holds five, so libraries fold:
/// - every *books* library with audiobooks joins one Audiobooks tab (an
///   e-book library has nothing that plays);
/// - *Collections* (box sets) become a row on the Movies page, and
///   *Playlists* a row on Home;
/// - past the tab limit, the rest go behind a "More" tab;
/// - kinds the app can't play yet (music, live TV) aren't shown;
/// - and any library the person hid stays out.
public struct SidebarPlan: Sendable, Equatable {
    public enum Entry: Sendable, Equatable {
        case library(BaseItem)
        /// All books libraries with audiobooks, as one tab.
        case audiobooks([BaseItem])
        /// Libraries that didn't fit.
        case more([BaseItem])
    }

    /// Where a library is in the app.
    public enum Placement: Sendable, Equatable {
        case tab
        case more
        /// In the Audiobooks tab, with any other books libraries.
        case audiobooks
        /// A row on the Movies page.
        case collectionsRow
        /// Playlists: a row on Home (a tab of their own pushed Videos behind More).
        case homeRow
        /// Left out in Settings.
        case hidden
        /// Nothing in it the app can play (yet), and why.
        case notPlayable(String)

        /// Whether it can be shown at all (a switch in Settings).
        public var canShow: Bool { if case .notPlayable = self { false } else { true } }
    }

    public struct Library: Sendable, Equatable, Identifiable {
        public var item: BaseItem
        public var placement: Placement
        public var id: String { item.id }
    }

    public static let maxLibraryTabs = 4
    public var entries: [Entry]
    /// Folded into the Movies page as a row.
    public var collections: [BaseItem]
    /// Playlists libraries, folded into Home as a row.
    public var playlists: [BaseItem] = []
    /// Every library on the server, in its order, and where it went.
    public var libraries: [Library] = []

    public static let supported: Set<String> = ["movies", "tvshows", "boxsets", "homevideos", "musicvideos", "books", "playlists"]

    /// "Playlists aren't supported yet" — what a kind the app can't play is.
    static func unsupported(_ type: String?) -> String {
        switch type {
        case "music": "Music isn't supported yet"
        case "livetv": "Live TV isn't supported yet"
        case "photos": "Photos aren't supported"
        default: "Not a kind of library \(Brand.displayName) plays"
        }
    }

    /// - Parameters:
    ///   - views: the server's libraries, in its order.
    ///   - maxTabs: library tabs at most (an iPhone's tab bar has room for fewer).
    ///   - hidden: libraries the person left out.
    ///   - hasAudiobooks: which books libraries hold any (the rest are e-books).
    public init(views: [BaseItem], maxTabs: Int = SidebarPlan.maxLibraryTabs, hidden: Set<String> = [], hasAudiobooks: (BaseItem) -> Bool) {
        var placement: [String: Placement] = [:]
        for view in views {
            if let type = view.collectionType, !Self.supported.contains(type) { placement[view.id] = .notPlayable(Self.unsupported(type)) }
            else if view.collectionType == "books", !hasAudiobooks(view) { placement[view.id] = .notPlayable("No audiobooks in it (e-books don't play)") }
            else if hidden.contains(view.id) { placement[view.id] = .hidden }
        }
        let shown = views.filter { placement[$0.id] == nil }
        let books = shown.filter { $0.collectionType == "books" }
        let hasMovies = shown.contains { $0.collectionType == "movies" }
        collections = hasMovies ? shown.filter { $0.collectionType == "boxsets" } : []
        for c in collections { placement[c.id] = .collectionsRow }
        playlists = shown.filter { $0.collectionType == "playlists" }
        for p in playlists { placement[p.id] = .homeRow }

        var tabs: [Entry] = []
        var addedBooks = false
        for view in shown {
            switch view.collectionType {
            case "books":
                placement[view.id] = .audiobooks
                if !addedBooks { tabs.append(.audiobooks(books)); addedBooks = true }
            case "boxsets" where hasMovies:
                continue
            case "playlists":
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
            for v in overflow { placement[v.id] = .more }
        }
        for case .library(let v) in tabs { placement[v.id] = .tab }
        entries = tabs
        libraries = views.map { Library(item: $0, placement: placement[$0.id] ?? .tab) }
    }

}
