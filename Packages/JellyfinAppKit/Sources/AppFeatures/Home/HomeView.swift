import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import Observation
import SwiftUI
import os

nonisolated struct BrowseSection: Identifiable, Codable, Sendable, Equatable {
    enum Style: String, Codable, Sendable { case poster, landscape, square }
    var id: String
    var title: String
    var items: [BaseItem]
    var style: Style
    var seeAll: ItemQuery?
    /// The line of copy under the title.
    var subtitle: String? = nil
    /// Everything behind "View all" (when known).
    var total: Int? = nil
    /// The library it's drawn from ("Movies") — the collection page's sentence starts with it.
    var library: String? = nil
    /// How "View all" narrows `seeAll`, so it opens a page of its own rather
    /// than the whole library re-sorted ("added in the last month",
    /// "rated 7.5+", "from the 2020s").
    var added: CollectionFilter.Added = .any
    var minRating: Double? = nil
    var decade: Int? = nil

    /// What "View all" opens: the narrowed query, or (a row with no query
    /// behind it, like Next Up) the whole row it was cut from.
    var seeAllSpec: GridSpec {
        guard let seeAll else { return GridSpec(title: title, items: items, library: library ?? title) }
        var filter = CollectionFilter(base: seeAll, libraryName: library ?? title)
        filter.added = added
        filter.minRating = minRating
        filter.decade = decade
        return GridSpec(title: title, filter: filter)
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.items.map(\.id) == b.items.map(\.id) }
}

@MainActor
@Observable
final class HomeModel {
    private(set) var sections: [BrowseSection] = []
    private(set) var error: String?
    private(set) var loadedOnce = false

    func load(_ session: UserSession, usage: [String: Double] = [:]) async {
        let key = "home-\(session.id)"
        if sections.isEmpty, let cached = await ContentCache.shared.value([BrowseSection].self, for: key), !cached.isEmpty {
            BlurHashCache.shared.prewarm(cached.flatMap(\.items))
            sections = cached
            LaunchClock.markFirstContent()
        }
        do {
            let fresh = try await Perf.measure("home.load", .homeLoad) { try await Self.fetch(session.client, usage: usage) }
            BlurHashCache.shared.prewarm(fresh.flatMap(\.items))
            if fresh != sections { sections = fresh }
            TopShelfWriter.update(fresh, client: session.client, usage: usage)
            error = nil
            LaunchClock.markFirstContent()
            await ContentCache.shared.store(fresh, for: key)
        } catch {
            if sections.isEmpty { self.error = error.localizedDescription }
        }
        loadedOnce = true
    }

    /// All home rows in parallel: total latency ≈ the slowest single request.
    nonisolated static func fetch(_ client: JellyfinClient, usage: [String: Double] = [:]) async throws -> [BrowseSection] {
        // More than a row shows: the rest is behind "View all".
        async let resume = client.resumeItems(limit: 50)
        async let nextUp = client.nextUp(limit: 50)
        async let views = client.userViews()

        let libraries = LibraryOrder.ordered(try await views.items, scores: usage).filter { $0.collectionType == "movies" || $0.collectionType == "tvshows" }
        let latest = try await withThrowingTaskGroup(of: (Int, BrowseSection).self) { group in
            for (i, lib) in libraries.enumerated() {
                group.addTask {
                    let items = try await client.latest(parentId: lib.id, limit: 20)
                    var q = ItemQuery(parentId: lib.id, includeItemTypes: lib.collectionType == "tvshows" ? [.series] : [.movie], sortBy: ["DateCreated", "SortName"], sortOrder: .descending)
                    q.limit = 100
                    return (i, BrowseSection(id: "latest-\(lib.collectionType ?? "x")-\(lib.id)", title: lib.name ?? "Library", items: items, style: .landscape, seeAll: q, library: lib.name))
                }
            }
            var out: [(Int, BrowseSection)] = []
            for try await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }

        var sections: [BrowseSection] = []
        let resumeItems = (try? await resume.items) ?? []
        if !resumeItems.isEmpty { sections.append(BrowseSection(id: "resume", title: "Continue Watching", items: resumeItems, style: .landscape, total: resumeItems.count)) }
        let nextItems = (try? await nextUp.items) ?? []
        if !nextItems.isEmpty { sections.append(BrowseSection(id: "nextup", title: "Next Up", items: nextItems, style: .landscape, total: nextItems.count)) }
        sections += latest.filter { !$0.items.isEmpty }
        return sections
    }
}

/// Tracks which item has focus *without* invalidating the screen that owns
/// it. Each card keeps a local @FocusState and reports here; only views that
/// read `featured` (hero header, backdrop) re-render. Debounced so flicking
/// across a row doesn't churn through backdrops.
@MainActor
@Observable
final class FocusTracker {
    private(set) var featured: BaseItem?
    /// The row with focus — immediate, not debounced (the shelf list moves
    /// it to the top as soon as focus enters it).
    private(set) var row: String?
    /// Called once focus has *rested* on a card (~350 ms): the user is
    /// probably about to open or play it, so start fetching now.
    @ObservationIgnored var onDwell: ((BaseItem) -> Void)?
    /// Every page's featured item, app-wide (the companion app shows it).
    static var onFeatured: ((BaseItem) -> Void)?
    @ObservationIgnored private var pending: Task<Void, Never>?

    func focused(_ item: BaseItem, row: String? = nil) {
        HitchMonitor.shared.noteActivity()
        if let row, row != self.row { self.row = row }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            if self?.featured?.id != item.id { self?.featured = item }
            FocusTracker.onFeatured?(item)
            try? await Task.sleep(for: .milliseconds(190))
            guard !Task.isCancelled else { return }
            self?.onDwell?(item)
        }
    }

    func seed(_ item: BaseItem?) {
        if featured == nil { featured = item }
    }
}

extension EnvironmentValues {
    @Entry var focusTracker: FocusTracker?
}

private struct ReportsFocus: ViewModifier {
    let item: BaseItem
    var row: String?
    @Environment(\.focusTracker) private var tracker
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, now in if now { tracker?.focused(item, row: row) } }
    }
}

extension View {
    func reportsFocus(_ item: BaseItem, row: String? = nil) -> some View { modifier(ReportsFocus(item: item, row: row)) }
    /// Runs `action` whenever this view gains focus.
    func onFocused(_ action: @escaping () -> Void) -> some View { modifier(OnFocused(action: action)) }
}

private struct OnFocused: ViewModifier {
    let action: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, now in if now { action() } }
    }
}

/// Hero + backdrop bound to the tracker: the only views that re-render on focus moves.
private struct BackgroundOnly: View {
    @Environment(\.theme) private var theme
    var body: some View { theme.backgroundGradient.ignoresSafeArea() }
}

struct TrackedBackdrop: View {
    let tracker: FocusTracker
    /// `-perfNoBackdrop`: the theme background only (device measurements).
    private static let off = ProcessInfo.processInfo.arguments.contains("-perfNoBackdrop")
    var body: some View {
        if Self.off { BackgroundOnly() } else { FocusBackdrop(tracker.featured) }
    }
}

struct TrackedHero: View {
    let tracker: FocusTracker
    var body: some View { HeroInfo(item: tracker.featured) }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var model = HomeModel()
    @State private var tracker = FocusTracker()
    @FocusState private var firstCardFocused: Bool

    var body: some View {
        let page = EditorialHome(sections: model.sections, userName: app.session?.account.userName)
        ZStack(alignment: .top) {
            TrackedBackdrop(tracker: tracker)
            CollectionList(sections: page.sections, firstCardFocus: $firstCardFocused, showsQueue: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(page.copy.greeting)
                        .font(.system(size: Layout.pageTitle, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Text(page.copy.lede)
                        .font(.title3)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: 1200, alignment: .leading)
                }
                .padding(.top, 10)
            }
            if let error = model.error {
                ContentUnavailableView("Can’t Reach Your Server", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if model.sections.isEmpty && model.loadedOnce {
                ContentUnavailableView("Your Libraries Are Empty", systemImage: "film.stack")
            }
        }
        .environment(\.focusTracker, tracker)
        .task {
            tracker.onDwell = { [app] item in Self.prefetch(item, app: app) }
            if let session = app.session { await model.load(session, usage: app.libraryUsage.scores) }
            app.queue.candidates = model.sections.first { $0.id == "nextup" }?.items ?? []
            tracker.seed(model.sections.first?.items.first)
        }
        // Where focus starts (only on appearing: it doesn't steer later moves,
        // which is what kept the sidebar from opening before).
        .defaultFocus($firstCardFocused, true)
        .claimsLaunchFocus($firstCardFocused, ready: !model.sections.isEmpty, key: "home")
        .hidesNavigationBar()
    }
}

/// Home's words: the fetched sections, retitled and described by `Editorial`.
struct EditorialHome {
    let copy: Editorial
    let sections: [BrowseSection]

    init(sections raw: [BrowseSection], userName: String?, now: Date = .now) {
        func items(_ prefix: String) -> [BaseItem] { raw.filter { $0.id.hasPrefix(prefix) }.flatMap(\.items) }
        let copy = Editorial(now: now, userName: userName, inProgress: items("resume"), nextUp: items("nextup"),
                             recentMovies: items("latest-movies"), recentShows: items("latest-tvshows"))
        self.copy = copy
        sections = raw.map { section in
            var s = section
            let words: Editorial.Copy
            switch section.id {
            case "resume": words = copy.resume
            case "nextup": words = copy.upNext
            default: words = copy.recent(section.items, library: section.title)
            }
            s.title = words.title
            s.subtitle = words.subtitle
            return s
        }
    }
}

extension HomeView {
    /// Shared by Home and Library: details + artwork for what's focused, and a
    /// PlaybackInfo prewarm for playable cards (Continue Watching / Next Up),
    /// so a single click starts playback with the round trip already done.
    static func prefetch(_ item: BaseItem, app: AppModel) {
        guard let client = app.session?.client else { return }
        DetailPrefetcher.shared.prefetch(item, client: client)
        if item.kind.isPlayable { app.prewarm(item) }
    }
}

/// Page opens on content, not the tab sidebar (like the TV app). Once only:
/// never yank focus back after the user has moved. Retries because the card
/// may not be in the focus tree on the first frame after data arrives.
private struct LaunchFocusClaim: ViewModifier {
    let binding: FocusState<Bool>.Binding
    let ready: Bool
    let key: String
    /// Per app launch, not per view: tvOS can rebuild a tab's page (opening
    /// the sidebar on tvOS 26.6 does), and a fresh page claiming focus again
    /// pulled focus straight back out of the sidebar.
    @MainActor static var claimed: Set<String> = []

    func body(content: Content) -> some View {
        content
            .onAppear { TraceFile.write("focus", "page \(key) appeared") }
            .task(id: ready) {
                guard ready, !Self.claimed.contains(key) else { return }
                Self.claimed.insert(key)
                TraceFile.write("focus", "page \(key) claims launch focus")
                for _ in 0..<20 where !binding.wrappedValue {
                    binding.wrappedValue = true
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
    }
}

extension View {
    func claimsLaunchFocus(_ binding: FocusState<Bool>.Binding, ready: Bool, key: String) -> some View {
        modifier(LaunchFocusClaim(binding: binding, ready: ready, key: key))
    }
}


/// The focused title's logo. Moving between titles, the logo's box resizes
/// to the new one's shape while the two crossfade, each drawn at its own
/// size — and the old one stays until the new one has loaded, so there's no
/// empty frame and no image drawn in the wrong box (the old flicker).
struct HeroLogo: View {
    let item: BaseItem
    @Environment(\.jellyfin) private var client
    @Environment(\.displayScale) private var scale
    @State private var shown: (key: String, image: CGImage)?
    static let box = CGSize(width: 520, height: 150)

    private var request: ImageRequest? {
        guard let client, let source = ArtworkSource.resolve(item, .logo) else { return nil }
        return source.request(client: client, pixelWidth: Int(Self.box.width * scale))
    }

    /// The logo fitted into the box (the box shrinks to it).
    private static func fitted(_ image: CGImage) -> CGSize {
        let aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        let width = min(box.width, box.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    var body: some View {
        let size = shown.map { Self.fitted($0.image) } ?? Self.box
        ZStack(alignment: .bottomLeading) {
            if let shown {
                Image(decorative: shown.image, scale: scale)
                    .resizable()
                    .scaledToFit()
                    .id(shown.key)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .frame(width: Self.box.width, height: Self.box.height, alignment: .bottomLeading)
        .task(id: request?.key) {
            guard let request, shown?.key != request.key else { return }
            var image = ImagePipeline.shared.cachedImage(for: request)
            if image == nil { image = try? await ImagePipeline.shared.image(for: request) }
            guard let image, !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.35)) { shown = (request.key, image) }
        }
    }
}

/// Logo/title + metadata + overview for the focused item.
struct HeroInfo: View {
    let item: BaseItem?
    @Environment(\.theme) private var theme
    @Environment(\.hideSpoilers) private var hideSpoilers

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            if let item {
                if ArtworkSource.resolve(item, .logo) != nil {
                    HeroLogo(item: item)
                } else {
                    Text(item.kind == .episode ? item.seriesName ?? "" : item.name ?? "")
                        .font(.system(size: Layout.pageTitle, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                }
                MetadataLine(item: item)
                if let overview = item.overview(hidingSpoilers: hideSpoilers) {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(3)
                        .frame(maxWidth: 1000, alignment: .leading)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: item?.id)
        .padding(.bottom, 36)       // breathing room above the first row
    }
}

struct MetadataLine: View {
    let item: BaseItem
    @Environment(\.theme) private var theme

    var body: some View {
        let parts = Self.parts(for: item)
        Text(parts.joined(separator: "  ·  "))
            .font(.callout.weight(.medium))
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
    }

    static func parts(for item: BaseItem) -> [String] {
        var parts: [String] = []
        if item.kind == .episode {
            parts.append([item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · "))
        }
        if let year = item.productionYear { parts.append(String(year)) }
        if let rating = item.officialRating { parts.append(rating) }
        if let runtime = item.runtime { parts.append(runtimeString(runtime)) }
        if let score = item.communityRating { parts.append("★ " + score.formatted(.number.precision(.fractionLength(1)))) }
        if let genres = item.genres, !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }
        return parts.filter { !$0.isEmpty }
    }

    static func runtimeString(_ d: Duration) -> String {
        let minutes = Int(d.components.seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

extension BaseItem {
    /// Select plays it (resuming): a specific episode, or anything already
    /// started. Everything else opens its page. Hold for the rest.
    var playsOnSelect: Bool { kind.isPlayable && (kind == .episode || resumePosition != nil) }
}

extension AppModel {
    /// What Select on a card does, everywhere.
    func select(_ item: BaseItem, navigate: NavigateAction) {
        if item.playsOnSelect { play(item) } else { navigate(.item(item)) }
    }
}

/// Hold Select on a card. Details comes first, so hold-then-click opens the
/// page of something whose Select plays it.
struct ItemContextMenu: View {
    let item: BaseItem
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate

    var body: some View {
        Button(item.kind == .episode ? "Episode Details" : "See Details", systemImage: "info.circle") { navigate(.item(item)) }
        if [.series, .episode, .movie].contains(item.kind) {
            Button("Background Noise", systemImage: "infinity") { app.playInBackground(item) }
        }
        if item.kind.isPlayable {
            Button("Play", systemImage: "play.fill") { app.play(item) }
            if item.resumePosition != nil {
                Button("Play from Beginning", systemImage: "gobackward") { app.play(item, resume: false) }
            }
            Button(app.queue.contains(item.id) ? "Remove from Queue" : "Add to Queue",
                   systemImage: app.queue.contains(item.id) ? "text.badge.checkmark" : "text.badge.plus") { app.queue.toggle(item) }
        }
        Button(item.isPlayed ? "Mark Unwatched" : "Mark Watched", systemImage: item.isPlayed ? "eye.slash" : "eye") {
            guard let client = app.session?.client else { return }
            Task { try? await client.setPlayed(!item.isPlayed, itemId: item.id) }
        }
        Button(item.isFavorite ? "Remove Favorite" : "Favorite", systemImage: item.isFavorite ? "heart.slash" : "heart") {
            guard let client = app.session?.client else { return }
            Task { try? await client.setFavorite(!item.isFavorite, itemId: item.id) }
        }
    }
}

/// `-benchmark`: animate through every shelf, down and back up, once,
/// with the hitch monitor scoring every frame. Results go to the log (and
/// the HUD) so `scripts/benchmark.sh` can collect them.
@MainActor
enum Benchmark {
    static func scroll(through ids: [String], select: (String) -> Void) async {
        try? await Task.sleep(for: .milliseconds(500))  // let launch settle
        Metrics.shared.reset()
        HitchMonitor.shared.start()
        HitchMonitor.shared.resetTotals()
        Perf.logger("benchmark").info("benchmark start: \(ids.count, privacy: .public) shelves, monitor running \(HitchMonitor.shared.isRunning, privacy: .public)")
        for _ in 0..<1 {                                 // one pass: < 10 s total
            for id in ids + ids.reversed() {
                HitchMonitor.shared.noteActivity()
                Perf.logger("benchmark").info("scroll → \(id, privacy: .public)")
                select(id)
                try? await Task.sleep(for: .milliseconds(600))
                // The view's task restarts when rows reload; a cancelled run
                // must not report (it would race through with no sleeps).
                if Task.isCancelled { return }
            }
        }
        Perf.logger("benchmark").info("benchmark end: \(Metrics.shared.summary(.frameTime)?.count ?? 0, privacy: .public) frames scored")
        let json = Metrics.shared.snapshotJSON()
        // To a file: os_log truncates messages past ~1 KB, and the snapshot
        // is bigger than that. scripts/benchmark.sh reads it from the container.
        let url = PerfRecorder.shared.latestURL.deletingLastPathComponent().appending(path: "benchmark.json")
        try? Data(json.utf8).write(to: url, options: .atomic)
        Perf.logger("benchmark").info("BENCHMARK written \(url.path, privacy: .public)")
    }
}

// MARK: - Navigation plumbing

/// Push a route onto the app's NavigationStack from anywhere below it.
struct NavigateAction {
    let push: (Route) -> Void
    func callAsFunction(_ route: Route) { push(route) }
}

extension EnvironmentValues {
    @Entry var navigate = NavigateAction { _ in }
}
