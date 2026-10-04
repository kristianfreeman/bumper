#if os(tvOS)
import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import Observation
import SwiftUI

@MainActor
@Observable
final class LibraryModel {
    private(set) var sections: [BrowseSection] = []
    private(set) var genreSections: [BrowseSection] = []

    /// "600 films, 42 you haven't seen."
    var lede: String? {
        guard let all = sections.first(where: { $0.id == "all" })?.total else { return nil }
        let unwatched = sections.first(where: { $0.id == "unwatched" })?.total ?? 0
        let noun = all == 1 ? "title" : "titles"
        return unwatched > 0 ? "\(all.formatted()) \(noun), \(unwatched.formatted()) you haven't seen." : "\(all.formatted()) \(noun)."
    }
    private var loadedGenres: Set<String> = []

    func load(library: BaseItem, client: JellyfinClient, collections: [BaseItem] = []) async {
        let key = "library-\(library.id)"
        if sections.isEmpty, let cached = await ContentCache.shared.value([BrowseSection].self, for: key) { sections = cached }
        let types = Self.types(for: library)

        func query(_ sort: [String], _ order: ItemSortOrder = .ascending, filters: [String] = [], limit: Int = 24) -> ItemQuery {
            var q = ItemQuery(parentId: library.id, includeItemTypes: types, sortBy: sort, sortOrder: order, limit: limit)
            q.filters = filters
            return q
        }
        let noun = Self.noun(for: library)
        var specs: [(String, String, ItemQuery, BrowseSection.Style)] = [
            ("recent", "Recently added", query(["DateCreated", "SortName"], .descending), .landscape),
            ("all", Self.allTitle(for: library), query(["SortName"]), .landscape),
            ("unwatched", "Haven't seen yet", query(["Random"], filters: ["IsUnplayed"]), .landscape),
            ("favorites", "Your favourites", query(["SortName"], filters: ["IsFavorite"]), .landscape),
            ("top", "Highest rated", query(["CommunityRating", "SortName"], .descending), .landscape),
            ("released", "Newest releases", query(["PremiereDate", "SortName"], .descending), .landscape),
        ]
        // Movies: the server's Collections (box sets) as a row, not a tab.
        if library.collectionType == "movies", let boxsets = collections.first {
            var q = ItemQuery(parentId: boxsets.id, includeItemTypes: [.boxSet], sortBy: ["SortName"], limit: 24)
            q.recursive = true
            specs.insert(("collections", "Collections", q, .landscape), at: min(2, specs.count))
        }
        let fresh = await withTaskGroup(of: (Int, BrowseSection?).self) { group in
            for (i, spec) in specs.enumerated() {
                group.addTask {
                    guard let page = try? await client.items(spec.2), !page.items.isEmpty else { return (i, nil) }
                    var all = spec.2
                    all.limit = 100
                    var section = BrowseSection(id: spec.0, title: spec.1, items: page.items, style: spec.3, seeAll: all)
                    section.total = page.totalRecordCount
                    section.library = library.name
                    section.subtitle = Self.subtitle(spec.0, total: page.totalRecordCount, noun: noun, first: page.items.first)
                    return (i, section)
                }
            }
            var out: [(Int, BrowseSection?)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        if !fresh.isEmpty {
            BlurHashCache.shared.prewarm(fresh.flatMap(\.items))
            sections = fresh
            await ContentCache.shared.store(fresh, for: key)
        }

        // Genre rows: one cheap list call; the rows themselves load lazily as
        // they scroll into view.
        if let genres = try? await client.genres(parentId: library.id).items {
            genreSections = genres.prefix(12).map { g in
                var q = query(["Random"], limit: 24)
                q.genres = [g.name ?? ""]
                var section = BrowseSection(id: "genre-\(g.name ?? g.id)", title: g.name ?? "", items: [], style: .landscape, seeAll: q, library: library.name)
                section.subtitle = "A few \((g.name ?? "").lowercased()) \(noun.plural) picked at random."
                return section
            }
        }
    }

    func loadGenre(_ id: String, client: JellyfinClient) async {
        guard !loadedGenres.contains(id), let idx = genreSections.firstIndex(where: { $0.id == id }), let q = genreSections[idx].seeAll else { return }
        loadedGenres.insert(id)
        if let page = try? await client.items(q) {
            guard !page.items.isEmpty else { genreSections.remove(at: idx); return }
            BlurHashCache.shared.prewarm(page.items)
            genreSections[idx].items = page.items
            genreSections[idx].seeAll?.sortBy = ["SortName"]
            genreSections[idx].seeAll?.limit = 100
        }
    }

    /// "film"/"films", "show"/"shows" — for the copy.
    nonisolated static func noun(for library: BaseItem) -> (singular: String, plural: String) {
        switch library.collectionType {
        case "movies": ("film", "films")
        case "tvshows": ("show", "shows")
        case "boxsets": ("collection", "collections")
        default: ("title", "titles")
        }
    }

    nonisolated static func subtitle(_ id: String, total: Int, noun: (singular: String, plural: String), first: BaseItem?) -> String? {
        let n = total == 1 ? "one \(noun.singular)" : "\(total.formatted()) \(noun.plural)"
        switch id {
        case "recent": return first.map { "Most recently, \($0.name ?? "something new")." }
        case "all": return "Every one of them, A to Z — \(n)."
        case "unwatched": return "\(n.prefix(1).uppercased() + n.dropFirst()) you haven't watched."
        case "favorites": return "The ones you've starred."
        case "top": return "What critics and viewers rate highest."
        case "released": return "The most recent premieres."
        case "collections": return "Films that belong together."
        default: return nil
        }
    }

    static func allTitle(for library: BaseItem) -> String {
        switch library.collectionType {
        case "movies": "All Movies"
        case "tvshows": "All Shows"
        case "boxsets": "All Collections"
        default: "All"
        }
    }

    static func types(for library: BaseItem) -> [ItemKind] {
        switch library.collectionType {
        case "movies": [.movie]
        case "tvshows": [.series]
        case "boxsets": [.boxSet]
        default: []
        }
    }
}

struct LibraryView: View {
    let library: BaseItem
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @State private var model = LibraryModel()
    @State private var tracker = FocusTracker()
    @FocusState private var firstCardFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            TrackedBackdrop(tracker: tracker)
            CollectionList(sections: model.sections + model.genreSections, firstCardFocus: $firstCardFocused, onNear: { id in
                guard let client = app.session?.client else { return }
                Task { await model.loadGenre(id, client: client) }
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(library.name ?? "Library").font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
                    if let lede = model.lede { Text(lede).font(.title3).foregroundStyle(.white.opacity(0.75)) }
                }
                .padding(.top, 20)
            }
        }
        .environment(\.focusTracker, tracker)
        .task {
            tracker.onDwell = { [app] item in HomeView.prefetch(item, app: app) }
            guard let client = app.session?.client else { return }
            await model.load(library: library, client: client, collections: app.collectionLibraries)
            tracker.seed(model.sections.first?.items.first)
        }
        .claimsLaunchFocus($firstCardFocused, ready: !model.sections.isEmpty, key: "library-\(library.id)")
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - More

/// Libraries without a tab of their own (see SidebarPlan).
struct MoreLibrariesView: View {
    let libraries: [BaseItem]
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text("More").font(.title2.bold()).foregroundStyle(theme.primaryText)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Layout.landscapeWidth), spacing: Layout.cardSpacing), count: 4), alignment: .leading, spacing: 50) {
                    ForEach(libraries) { library in
                        LandscapeCard(library, kind: .poster) { navigate(.library(library)) }
                    }
                }
                .focusSection()
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        .background(theme.backgroundGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Collection page ("View all")

@MainActor
@Observable
final class CollectionPageModel {
    private(set) var items: [BaseItem] = []
    private(set) var total: Int?
    private(set) var genres: [String] = []
    private var exhausted = false
    private var loading = false
    private var nextIndex = 0
    private var generation = 0

    func reset() {
        items = []
        total = nil
        exhausted = false
        nextIndex = 0
        generation += 1
    }

    /// Next page: the server filters what it can; when added and length are
    /// checked here, and "added within" stops at the first item older than it.
    func loadMore(_ filter: CollectionFilter, client: JellyfinClient) async {
        guard !loading, !exhausted else { return }
        loading = true
        defer { loading = false }
        let generation = generation
        var q = filter.query
        q.startIndex = nextIndex
        q.limit = 100
        guard let page = try? await client.items(q), generation == self.generation else { return }
        nextIndex += page.items.count
        let kept = page.items.filter { filter.matches($0) }
        BlurHashCache.shared.prewarm(kept)
        items += kept
        let clientSide = filter.added != .any || filter.maxMinutes != nil
        total = clientSide ? nil : page.totalRecordCount
        let pastCutoff = filter.addedCutoff().map { cutoff in page.items.last.map { ($0.dateCreated ?? .distantPast) < cutoff } ?? true } ?? false
        exhausted = page.items.isEmpty || nextIndex >= page.totalRecordCount || pastCutoff
    }

    func loadGenres(parentId: String?, client: JellyfinClient) async {
        guard genres.isEmpty, let list = try? await client.genres(parentId: parentId).items else { return }
        genres = list.compactMap(\.name)
    }
}

/// A whole collection, under a sentence that says what it is — every part
/// of which is a pill you can change, remove or add to, or set by asking.
struct CollectionPage: View {
    let spec: GridSpec
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme
    @State private var filter: CollectionFilter
    @State private var model = CollectionPageModel()
    @State private var asking = false
    @State private var words = ""
    @State private var understood: String?
    @State private var width: CGFloat = 1600

    init(spec: GridSpec) {
        self.spec = spec
        _filter = State(initialValue: spec.filter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(spec.title).font(.system(size: 56, weight: .bold)).foregroundStyle(theme.primaryText)
                    FilterSentence(filter: $filter, genres: model.genres) { asking = true }
                    if let understood {
                        Text(understood).font(.callout).foregroundStyle(theme.secondaryText).transition(.opacity)
                    } else if let total = model.total {
                        Text(total == 1 ? "One title." : "\(total.formatted()) titles.").font(.callout).foregroundStyle(theme.secondaryText)
                    }
                }
                .focusSection()
                let columns = 4
                let cardWidth = ((width - CGFloat(columns - 1) * Layout.cardSpacing) / CGFloat(columns)).rounded(.down)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: Layout.cardSpacing, alignment: .top), count: columns),
                          alignment: .leading, spacing: 44) {
                    ForEach(model.items) { item in
                        LandscapeCard(item, width: cardWidth) { navigate(.item(item)) }
                            .contextMenu { ItemContextMenu(item: item) }
                            .onAppear {
                                if model.items.count > 20, item.id == model.items[model.items.count - 21].id { loadMore() }
                                else if item.id == model.items.last?.id { loadMore() }
                            }
                    }
                }
                .focusSection()
                if model.items.isEmpty, model.total == 0 || model.total == nil {
                    Text("Nothing matches — try removing a part of the sentence.").font(.callout).foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 50)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * Layout.horizontalMargin } action: { width = $0 }
        }
        .scrollClipDisabled()
        .background(theme.backgroundGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: filter) {
            model.reset()
            loadMore()
        }
        .task {
            guard let client = app.session?.client else { return }
            await model.loadGenres(parentId: spec.filter.base.parentId, client: client)
        }
        .alert("What are you in the mood for?", isPresented: $asking) {
            TextField("Something funny from the 80s, under 90 minutes", text: $words)
                .onSubmit { ask(); asking = false }                 // Done on the keyboard (or after dictating) applies it
            Button("Find") { ask() }
            Button("Cancel", role: .cancel) { words = "" }
        } message: {
            Text("Say it or type it.")
        }
        .animation(.easeOut(duration: 0.2), value: filter)
    }

    private func loadMore() {
        guard let client = app.session?.client else { return }
        let filter = filter
        Task { await model.loadMore(filter, client: client) }
    }

    private func ask() {
        let said = words.trimmingCharacters(in: .whitespaces)
        words = ""
        guard !said.isEmpty else { return }
        let current = filter
        Task {
            switch await app.search.understand(said, in: current, genres: model.genres) {
            case .filter(let next, let changed, _):
                understood = "Showing " + changed.map(next.text).joined(separator: ", ") + "."
                filter = next
            case .title(let term):
                var next = current
                next.searchTerm = term
                understood = "Looking for titles matching “\(term)”."
                filter = next
            }
            TraceFile.write("collection", "ask → \(filter.sentence)")
        }
    }
}

/// "Movies · added this week · unwatched · Add · Sorted by name · Ask" —
/// every part a pill that always shows its words. Selecting one opens a
/// row of choices beneath (no menus: focus stays on the page, nothing
/// collapses); picking a choice applies it and closes the row.
struct FilterSentence: View {
    @Binding var filter: CollectionFilter
    let genres: [String]
    let ask: () -> Void
    @State private var editing: Editing?
    @FocusState private var focus: Focus?

    enum Editing: Hashable { case part(CollectionFilter.Part), add, sort }
    enum Focus: Hashable { case part(CollectionFilter.Part), add, sort, ask, option(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FlowLayout(spacing: 14) {
                Text(filter.libraryName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(height: 64)
                ForEach(filter.parts, id: \.self) { part in
                    Pill(filter.text(part), systemImage: symbol(part), size: .small, active: true, alwaysShowsTitle: true) { toggle(.part(part)) }
                        .focused($focus, equals: .part(part))
                        .accessibilityIdentifier("filter.\(part.rawValue)")
                }
                Pill("Add", systemImage: "plus", size: .small, active: editing == .add, alwaysShowsTitle: true) { toggle(.add) }
                    .focused($focus, equals: .add)
                    .accessibilityIdentifier("filter.add")
                Pill(filter.sort == .name ? "Sorted A–Z" : "Sorted by \(filter.sortTitle.lowercased())", systemImage: "arrow.up.arrow.down", size: .small, active: editing == .sort, alwaysShowsTitle: true) { toggle(.sort) }
                    .focused($focus, equals: .sort)
                    .accessibilityIdentifier("filter.sort")
                Pill("Ask", systemImage: "mic", size: .small, alwaysShowsTitle: true, action: ask)
                    .focused($focus, equals: .ask)
                    .accessibilityIdentifier("filter.ask")
            }
            .focusSection()
            if let editing {
                ChoiceRow(choices: choices(for: editing), focus: $focus) { choice in
                    choose(choice, in: editing)
                }
                .focusSection()
                .id(editing)
            }
        }
        // On every change of row (one row replacing another doesn't "appear").
        .onChange(of: editing) { _, now in if let now { focusFirstChoice(in: now) } }
        .onExitCommand(perform: editing == nil ? nil : { close() })
    }

    // MARK: Choices

    struct Choice: Identifiable, Hashable {
        let id: String
        let title: String
        var symbol: String? = nil
        var current = false
        var destructive = false
    }

    private func choices(for editing: Editing) -> [Choice] {
        switch editing {
        case .add:
            return CollectionFilter.Part.allCases.filter { $0 != .search && !filter.parts.contains($0) }.map { Choice(id: "add.\($0.rawValue)", title: title($0), symbol: symbol($0)) }
        case .sort:
            return CollectionFilter.Sort.allCases.map { sort in
                var copy = filter
                copy.sort = sort
                return Choice(id: "sort.\(sort.rawValue)", title: copy.sortTitle, current: filter.sort == sort)
            }
        case .part(let part):
            var list = options(for: part)
            if filter.parts.contains(part) { list.append(Choice(id: "remove", title: "Remove", symbol: "xmark", destructive: true)) }
            return list
        }
    }

    private func options(for part: CollectionFilter.Part) -> [Choice] {
        switch part {
        case .search:
            return []
        case .added:
            return [CollectionFilter.Added.week, .month, .year].map { Choice(id: "added.\($0.rawValue)", title: label($0), current: filter.added == $0) }
        case .watched:
            return [Choice(id: "watched.unwatched", title: "Unwatched", current: filter.watched == .unwatched),
                    Choice(id: "watched.watched", title: "Watched", current: filter.watched == .watched)]
        case .favourites:
            return [Choice(id: "favourites.on", title: "Favourites only", current: filter.favourites)]
        case .genre:
            return genres.map { Choice(id: "genre.\($0)", title: $0, current: filter.genre == $0) }
        case .decade:
            return [2020, 2010, 2000, 1990, 1980, 1970, 1960, 1950].map { Choice(id: "decade.\($0)", title: "\($0)s", current: filter.decade == $0) }
        case .length:
            return [60, 90, 120, 150].map { Choice(id: "length.\($0)", title: $0 % 60 == 0 ? "Under \($0 / 60) h" : "Under \($0) min", current: filter.maxMinutes == $0) }
        case .rating:
            return [6.0, 7.0, 7.5, 8.0, 8.5].map { Choice(id: "rating.\($0)", title: "\($0.formatted())+", current: filter.minRating == $0) }
        }
    }

    private func choose(_ choice: Choice, in editing: Editing) {
        switch editing {
        case .add:
            if let part = CollectionFilter.Part(rawValue: String(choice.id.dropFirst(4))) {
                self.editing = .part(part)                       // now pick its value
            }
            return
        case .sort:
            if let sort = CollectionFilter.Sort(rawValue: String(choice.id.dropFirst(5))) { filter.sort = sort }
            close(focusing: .sort)
            return
        case .part(let part):
            if choice.id == "remove" {
                filter.clear(part)
                close(focusing: .add)
                return
            }
            let value = choice.id.split(separator: ".", maxSplits: 1).last.map(String.init) ?? ""
            switch part {
            case .search: break
            case .added: filter.added = CollectionFilter.Added(rawValue: value) ?? .any
            case .watched: filter.watched = CollectionFilter.Watched(rawValue: value) ?? .any
            case .favourites: filter.favourites = true
            case .genre: filter.genre = value
            case .decade: filter.decade = Int(value)
            case .length: filter.maxMinutes = Int(value)
            case .rating: filter.minRating = Double(value)
            }
            close(focusing: .part(part))
        }
    }

    private func toggle(_ e: Editing) { editing = editing == e ? nil : e }

    private func close(focusing target: Focus? = nil) {
        let fallback: Focus? = switch editing {
        case .part(let p): .part(p)
        case .add: .add
        case .sort: .sort
        case nil: nil
        }
        editing = nil
        let wanted = target ?? fallback
        Task {
            // The pill may only exist after this render (a part just added),
            // and the closing row takes focus with it: settle it on the pill.
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(40))
                focus = wanted
            }
        }
    }

    private func focusFirstChoice(in editing: Editing) {
        let list = choices(for: editing)
        guard let target = list.first(where: \.current) ?? list.first else { return }
        Task {
            // The row replacing another (Add → a part's values) takes focus
            // away mid-swap; keep placing it until the swap has settled.
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(50))
                guard self.editing == editing else { return }
                if case .option = focus { if focus == .option(target.id) { return } else { continue } }   // it's in the row: leave it
                focus = .option(target.id)
            }
        }
    }

    // MARK: Words

    private func label(_ a: CollectionFilter.Added) -> String {
        switch a {
        case .any: "Any time"
        case .week: "This week"
        case .month: "In the last month"
        case .year: "This year"
        }
    }

    private func title(_ part: CollectionFilter.Part) -> String {
        switch part {
        case .search: "Title"
        case .added: "When added"
        case .watched: "Watched or not"
        case .favourites: "Favourites"
        case .genre: "Genre"
        case .decade: "Decade"
        case .length: "Length"
        case .rating: "Rating"
        }
    }

    private func symbol(_ part: CollectionFilter.Part) -> String {
        switch part {
        case .search: "magnifyingglass"
        case .added: "calendar"
        case .watched: "eye"
        case .favourites: "heart.fill"
        case .genre: "theatermasks"
        case .decade: "clock.arrow.circlepath"
        case .length: "timer"
        case .rating: "star.fill"
        }
    }

    /// One row of choices, scrolling sideways when there are many (genres).
    private struct ChoiceRow: View {
        let choices: [Choice]
        var focus: FocusState<Focus?>.Binding
        let pick: (Choice) -> Void

        var body: some View {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(choices) { choice in
                        Pill(choice.title, systemImage: choice.symbol ?? (choice.current ? "checkmark" : "circle"), size: .small,
                             active: choice.current, alwaysShowsTitle: true) { pick(choice) }
                            .focused(focus, equals: .option(choice.id))
                            .accessibilityIdentifier("filter.option.\(choice.id)")
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 6)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y + (line > 0 ? 0 : 0)), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
#endif
