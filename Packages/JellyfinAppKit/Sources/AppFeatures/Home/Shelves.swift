import AppCore
import Foundation
import DesignSystem
import Instrumentation
import JellyfinAPI
import Observation

/// The rows past a page's first few — every collection, each genre, "Because
/// you watched", the decades: Home and the libraries are made of them, Netflix
/// style, so most of what you'd want is a row away. Each is only a title and
/// where its cards come from until it's about to scroll into view; then it
/// loads, and a row that comes back empty goes.
nonisolated enum Shelves {
    /// Where a row's cards come from.
    enum Source: Codable, Sendable, Hashable {
        case query(ItemQuery)
        /// Like this one (the server's Similar).
        case similar(String)
    }

    /// Cards in a row; "View all" has the rest.
    static let rowLimit = 24

    // MARK: Home

    /// Home's rows after what's new: because you watched, the best rated,
    /// what you haven't seen, genres, every collection, something different.
    nonisolated static func home(libraries: [BaseItem], collections: BaseItem?, client: JellyfinClient) async -> [BrowseSection] {
        let movies = libraries.filter { $0.collectionType == "movies" }
        let kinds: [ItemKind] = libraries.contains { $0.collectionType == "tvshows" } ? (movies.isEmpty ? [.series] : [.movie, .series]) : [.movie]
        async let because = becauseYouWatched(parentId: nil, kinds: kinds, client: client, count: 2)
        async let genres = genreRows(parentId: nil, listedIn: libraries.map(\.id), kinds: kinds, client: client, max: 10, prefix: "home")
        async let boxsets = collectionRows(collections, client: client, max: 16)

        var rows = await because
        func row(_ id: String, _ title: String, _ subtitle: String?, sort: [String], order: ItemSortOrder = .descending,
                 filters: [String] = [], minRating: Double? = nil, types: [ItemKind] = kinds) -> BrowseSection {
            var q = ItemQuery(includeItemTypes: types, sortBy: sort, sortOrder: order, limit: rowLimit)
            q.filters = filters
            q.minCommunityRating = minRating
            return shelf("home-\(id)", title, subtitle: subtitle, q)
        }
        if !movies.isEmpty {
            rows.append(row("top", "Highest Rated Films", "Rated 7.5 and up", sort: ["CommunityRating", "SortName"], minRating: 7.5, types: [.movie]))
            rows.append(row("unseen", "Films You Haven't Seen", nil, sort: ["Random"], filters: ["IsUnplayed"], types: [.movie]))
        }
        let g = await genres
        rows += g.prefix(4)
        if let first = await boxsets.first { rows.append(first) }
        rows += g.dropFirst(4).prefix(3)
        rows.append(row("different", "Something Different", "A few at random from everything", sort: ["Random"]))
        rows += await boxsets.dropFirst()
        rows += g.dropFirst(7)
        if !movies.isEmpty {
            rows.append(row("favourites", "Your Favourites", nil, sort: ["SortName"], order: .ascending, filters: ["IsFavorite"]))
        }
        return Spotlight.placed(in: rows)
    }

    // MARK: A library

    /// A Movies or Shows page's rows after its own first few.
    nonisolated static func library(_ library: BaseItem, collections: BaseItem?, client: JellyfinClient, now: Date = .now) async -> [BrowseSection] {
        let kinds = LibraryModel.types(for: library)
        let movies = library.collectionType == "movies"
        async let because = becauseYouWatched(parentId: library.id, kinds: kinds, client: client, count: 2)
        async let genres = genreRows(parentId: library.id, listedIn: [library.id], kinds: kinds, client: client, max: 20, prefix: library.id)
        async let boxsets = movies ? collectionRows(collections, client: client, max: 60) : []

        var rows = await because
        let g = await genres
        rows += g.prefix(5)
        rows += await boxsets.prefix(6)
        rows += g.dropFirst(5)
        // The decades, newest first: what's there from each.
        let decade = Calendar.current.component(.year, from: now) / 10 * 10
        for d in stride(from: decade, through: 1950, by: -10) {
            var q = ItemQuery(parentId: library.id, includeItemTypes: kinds, sortBy: ["Random"], limit: rowLimit)
            q.years = Array(d..<(d + 10))
            var s = shelf("\(library.id)-decade-\(d)", "The \(String(d).suffix(2))s", subtitle: nil, q, line: .decade)
            if d >= 2000 { s.title = "The \(d)s" }
            s.library = library.name
            rows.append(s)
        }
        rows += await boxsets.dropFirst(6)
        return Spotlight.placed(in: rows)
    }

    // MARK: Filling a row

    /// A row's cards, when it comes near, and how many there are in all
    /// (a query's; nil for Similar).
    nonisolated static func items(for source: Source, client: JellyfinClient) async -> (items: [BaseItem], total: Int?) {
        switch source {
        case .query(let q):
            guard let page = try? await client.items(q) else { return ([], nil) }
            return (page.items, page.totalRecordCount)
        case .similar(let id): return ((try? await client.similar(to: id, limit: rowLimit))?.items ?? [], nil)
        }
    }


    // MARK: Kinds of row

    /// A row of `q`, with "View all" behind it: the whole of it by name.
    /// Posters: the most colourful, most recognisable art a film has, and
    /// more of them across. (Because You Watched keeps its wide cards.)
    /// `line`: the line under the title, written from the row's films when
    /// they come (`RowLine`); a blank one holds its place until then, so
    /// nothing moves.
    nonisolated static func shelf(_ id: String, _ title: String, subtitle: String?, _ q: ItemQuery, line: RowLine.Kind? = nil) -> BrowseSection {
        var all = q
        all.limit = 100
        if all.sortBy == ["Random"] { all.sortBy = ["SortName"]; all.sortOrder = .ascending }
        var s = BrowseSection(id: id, title: title, items: [], style: .poster, scrolls: true, seeAll: all)
        s.subtitle = subtitle ?? (line == nil ? nil : " ")
        s.source = .query(q)
        s.line = line
        return s
    }

    /// "Because you watched Heat": like the last things finished.
    nonisolated static func becauseYouWatched(parentId: String?, kinds: [ItemKind], client: JellyfinClient, count: Int) async -> [BrowseSection] {
        var q = ItemQuery(parentId: parentId, includeItemTypes: kinds, sortBy: ["DatePlayed"], sortOrder: .descending, limit: count)
        q.filters = ["IsPlayed"]
        q.fields = []
        let played = (try? await client.items(q))?.items ?? []
        return played.map { item in
            var s = BrowseSection(id: "because-\(parentId ?? "home")-\(item.id)", title: "Because You Watched \(item.name ?? "That")", items: [], style: .landscape, scrolls: true)
            s.source = .similar(item.id)
            return s
        }
    }

    /// The genres with the most here, biggest first (a count for each, in
    /// parallel; a genre only episodes carry counts none and is left out).
    /// `listedIn`: the libraries whose genres are counted (not music's).
    nonisolated static func genreRows(parentId: String?, listedIn: [String], kinds: [ItemKind], client: JellyfinClient, max: Int, prefix: String) async -> [BrowseSection] {
        var genres: [BaseItem] = []
        for id in listedIn {
            for g in (try? await client.genres(parentId: id).items) ?? [] where !genres.contains(where: { $0.name == g.name }) { genres.append(g) }
        }
        let counted = await withTaskGroup(of: (BaseItem, Int).self) { group in
            for g in genres {
                group.addTask {
                    var q = ItemQuery(parentId: parentId, includeItemTypes: kinds, limit: 1)
                    q.genres = [g.name ?? ""]
                    q.fields = []
                    return (g, (try? await client.items(q))?.totalRecordCount ?? 0)
                }
            }
            var out: [(BaseItem, Int)] = []
            for await r in group where r.1 > 0 { out.append(r) }
            return out.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.name ?? "") < ($1.0.name ?? "") }
        }
        return counted.prefix(max).map { g, count in
            var q = ItemQuery(parentId: parentId, includeItemTypes: kinds, sortBy: ["Random"], limit: rowLimit)
            q.genres = [g.name ?? ""]
            var s = shelf("genre-\(prefix)-\(g.name ?? g.id)", g.name ?? "", subtitle: nil, q, line: .genre)
            s.total = count
            return s
        }
    }

    /// Every collection (box set) as a row of its own, newest first; the
    /// films in each in the order they came out.
    nonisolated static func collectionRows(_ collections: BaseItem?, client: JellyfinClient, max: Int) async -> [BrowseSection] {
        guard let collections else { return [] }
        var q = ItemQuery(parentId: collections.id, includeItemTypes: [.boxSet], sortBy: ["DateCreated", "SortName"], sortOrder: .descending, limit: max)
        q.fields = []
        let sets = (try? await client.items(q))?.items ?? []
        return sets.map { set in
            let films = ItemQuery(parentId: set.id, sortBy: ["ProductionYear", "SortName"], limit: rowLimit)
            var s = shelf("collection-\(set.id)", set.name ?? "Collection", subtitle: nil, films, line: .collection)
            s.seeAll = nil                        // the collection's own page is behind its name
            s.collection = set
            return s
        }
    }
}

/// Rows that fill as they come into view: the page asks when one is near.
@MainActor
@Observable
final class LazyShelves {
    private(set) var sections: [BrowseSection] = []
    @ObservationIgnored private var asked: Set<String> = []
    /// Films already in a spotlight on the page: each is in one only.
    @ObservationIgnored private var spotlit: Set<String> = []

    /// A new set of rows: those already filled keep their cards.
    func replace(_ rows: [BrowseSection]) {
        let filled = Dictionary(sections.filter { !$0.items.isEmpty }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        sections = rows.map { filled[$0.id] ?? $0 }
        asked = asked.intersection(Set(filled.keys))
        spotlit = Set(sections.filter { $0.spotlight != nil }.flatMap { $0.items.map(\.id) })
    }

    /// A row's about to show: its cards (once). Empty, it goes.
    func near(_ id: String, client: JellyfinClient) async {
        // A spotlight fills from its row: that row's cards first (if it
        // hasn't them yet, it fills the spotlight as it does).
        if let row = sections.first(where: { $0.id == id }), let below = row.spotlight {
            await near(below, client: client)
            await fillSpotlight(above: below, client: client)
            return
        }
        guard !asked.contains(id), let row = sections.first(where: { $0.id == id }), let source = row.source, row.items.isEmpty else { return }
        asked.insert(id)
        let (items, total) = await Shelves.items(for: source, client: client)
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
        if items.isEmpty {
            sections.remove(at: i)
            sections.removeAll { $0.spotlight == id }        // nothing for its spotlight either
            return
        }
        BlurHashCache.shared.prewarm(items)
        var filled = sections[i]
        filled.items = items
        if let line = filled.line {
            // Blank when there's nothing worth saying: the place stays, nothing moves.
            filled.subtitle = RowLine.make(line, items: items, total: filled.total ?? total) ?? " "
        }
        sections[i] = filled
        await fillSpotlight(above: id, client: client)
    }

    /// The spotlight over row `below`, once that row has its cards: the best
    /// of them for it, with what it's about (one item's details). None that
    /// will do: the spotlight goes.
    private func fillSpotlight(above below: String, client: JellyfinClient) async {
        guard let spot = sections.first(where: { $0.spotlight == below }), !asked.contains(spot.id),
              let items = sections.first(where: { $0.id == below })?.items, !items.isEmpty else { return }
        asked.insert(spot.id)
        for candidate in Spotlight.candidates(items, excluding: spotlit).prefix(3) {
            guard let full = try? await client.item(id: candidate.id, fields: ItemField.hero),
                  !(full.overview ?? "").isEmpty else { continue }
            spotlit.insert(full.id)
            if let i = sections.firstIndex(where: { $0.id == spot.id }) { sections[i].items = [full] }
            return
        }
        sections.removeAll { $0.id == spot.id }
    }
}
