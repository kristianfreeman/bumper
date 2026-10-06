import AppCore
import DesignSystem
import Darwin
import Foundation
import Instrumentation
import JellyfinAPI
public import SwiftUI

/// Public entry point used by the app target.
public struct AppRoot: View {
    @State private var app = AppModel()
    let cast: CastLink?
    let castPanel: AnyView?

    /// `cast`, `castPanel`: the iPhone/iPad's link to an Apple TV, behind the
    /// TV button in the corner (finding it, then steering it).
    public init(cast: CastLink? = nil, castPanel: AnyView? = nil) {
        self.cast = cast
        self.castPanel = castPanel
    }

    public var body: some View {
        RootView()
            .environment(\.castLink, cast)
            .environment(\.castPanel, castPanel)
            .environment(app)
            .environment(app.settings)
            .environment(app.themes)
            .environment(\.theme, app.themes.theme)
            .environment(\.jellyfin, app.session?.client)
            .environment(\.hideSpoilers, app.settings.hideSpoilers)
            .environment(\.downloadStore, app.downloads)
            .preferredColorScheme(app.themes.theme.colorScheme)
            .tint(app.themes.theme.accent)
            .onOpenURL { app.open($0) }                     // the Top Shelf: bumper://play/<id>
            .onAppear { app.cast = cast }       // Play while connected goes to the TV (the views read it from the environment)
    }

    /// Call from the App's init, as early as possible.
    public static func markProcessStart() {
        LaunchClock.start = .now
        // Kernel exec → here: dyld, static initializers, and paging in the
        // binary and its frameworks.
        if let exec = processStartDate() {
            let ms = Date().timeIntervalSince(exec) * 1000
            Metrics.shared.record(.launchPreMain, value: ms)
            Perf.event("launch.preMain", "\(Int(ms)) ms")
        }
    }

    private static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            if let session = app.session {
                MainTabView(session: session, initialTab: app.options.route == "search" ? "search" : nil)
                    .id(session.id)
                    .fullScreen(isPresented: $app.showsAudiobook) {
                        if let player = app.audiobook {
                            AudiobookNowPlayingView(player: player)
                                .environment(app)
                                .environment(\.theme, theme)
                                .environment(\.jellyfin, app.session?.client)
                        }
                    }
            } else {
                OnboardingView()
            }
        }
        .overlay(alignment: .topTrailing) {
            if app.showsPerformanceHUD {
                PerfHUD().padding(40).allowsHitTesting(false)
            }
        }
        .onAppear { PerfRecorder.shared.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.refreshFromOtherDevices() }
            if phase != .active { PerfRecorder.shared.writeSession() }
        }
        .fullScreen(item: $app.playback) { request in
            PlayerView(request: request)
                .environment(app)
                .environment(\.theme, theme)
                .environment(\.jellyfin, app.session?.client)
        }
    }
}

nonisolated enum Route: Hashable, Sendable {
    case item(BaseItem)
    case library(BaseItem)
    case grid(GridSpec)
    case settings(String)          // deep links / screenshots: "root", "subtitles", …
    case profile
    case audiobook(String)
    case queue
    case downloads
    case downloadedShow(String)
}

nonisolated struct GridSpec: Hashable, Sendable {
    var title: String
    var filter: CollectionFilter
    /// A fixed list instead of a query (a Home row with no query behind it:
    /// Continue Watching, Next Up). No sentence to change.
    var items: [BaseItem]? = nil

    init(title: String, items: [BaseItem], library: String) {
        self.title = title
        self.items = items
        filter = CollectionFilter(base: ItemQuery(), libraryName: library)
    }

    // By what it shows, not every field of every item it carries (the
    // navigation path compares and hashes its pages on every change).
    static func == (a: Self, b: Self) -> Bool {
        a.title == b.title && a.filter == b.filter && a.items?.map(\.id) == b.items?.map(\.id)
    }

    func hash(into h: inout Hasher) {
        h.combine(title)
        h.combine(filter)
        h.combine(items?.map(\.id))
    }

    init(title: String, query: ItemQuery, library: String) {
        self.title = title
        filter = CollectionFilter(base: query, libraryName: library)
    }

    init(title: String, filter: CollectionFilter) {
        self.title = title
        self.filter = filter
    }
}

struct MainTabView: View {
    let session: UserSession
    @Environment(AppModel.self) private var app
    @Environment(\.castLink) private var cast

    @State private var plan = SidebarPlan(views: [], maxTabs: MainTabView.libraryTabs, hasAudiobooks: { _ in false })
    /// Books libraries found to hold audiobooks (nil: not asked yet).
    @State private var audiobookLibraries: Set<String>?
    @State private var selection = "home"
    #if os(tvOS)
    /// Your picture for the tab bar, round, drawn once it's loaded.
    @State private var profileIcon: UIImage?
    #endif
    #if os(macOS)
    /// The Mac: each place's pushed pages, and the places built so far.
    @State private var paths: [String: [Route]] = [:]
    @State private var visited: Set<String> = []
    #endif

    init(session: UserSession, initialTab: String? = nil) {
        self.session = session
        _selection = State(initialValue: initialTab ?? "home")
    }

    /// The places run along the top, like the Music app's: the TV's and the
    /// iPad's floating tab bar, the Mac's segmented control in the window
    /// toolbar. An iPhone has its tab bar at the bottom.
    var body: some View {
        #if os(macOS)
        macShell
        #elseif os(tvOS)
        // One stack around the tabs: a pushed page covers the whole screen,
        // tab bar and all, like the TV app's.
        RoutedStack(initial: app.launchRoute) { tabs.hidesNavigationBarEntirely() }
            .task { await loadLibraries() }
            .onChange(of: app.settings.hiddenLibraries) { _, _ in reapply() }
            .task(id: session.account.imageTag) { profileIcon = await ProfileIcon.make(session: session) }
            .task { await tabSwitchTest() }
        #else
        // A stack per tab (each keeps its own history, and the tab bar stays
        // as pages are pushed), with the TV's bar above the tabs.
        tabs
            .castBar(cast)
            .task { await loadLibraries() }
            .onChange(of: app.settings.hiddenLibraries) { _, _ in reapply() }
            .task { await tabSwitchTest() }
        #endif
    }

    /// Tests: `-tabSwitchTest` goes through every place twice, timing the
    /// frames (switching is what the places bar is for; it must be instant).
    private func tabSwitchTest() async {
        guard ProcessInfo.processInfo.arguments.contains("-tabSwitchTest") else { return }
        try? await Task.sleep(for: .seconds(3))
        Metrics.shared.reset()
        HitchMonitor.shared.start()
        HitchMonitor.shared.resetTotals()
        let ids = places.map(\.id).filter { $0 != "search" }
        // First visits build each page; after that a switch only shows one.
        for label in ["tabs, first visit", "tabs, switching back"] {
            var each: [String] = []
            for id in ids {
                Metrics.shared.reset()
                let start = ContinuousClock.now
                selection = id
                // The main thread is busy until the switch has been laid out
                // and committed: the time until it next runs anything else.
                await withCheckedContinuation { done in DispatchQueue.main.async { DispatchQueue.main.async { done.resume() } } }
                let busy = start.duration(to: .now).milliseconds
                for _ in 0..<6 { HitchMonitor.shared.noteActivity(); try? await Task.sleep(for: .milliseconds(100)) }
                each.append("\(id) \(Int(busy)) ms busy, frame \(Int(Metrics.shared.summary(.frameTime)?.max ?? 0)) ms")
            }
            TraceFile.write("benchmark", "\(label), worst frame: \(each.joined(separator: ", "))")
        }
    }

    /// An iPhone's tab bar holds five: Home, three libraries (the rest
    /// behind More) and Search. There, and on an iPad (whose floating bar
    /// shares the navigation bar's row), Downloads and Settings are in the
    /// profile menu instead.
    private static var phone: Bool { Layout.device == .phone }
    private static var placesInMenu: Bool { Layout.device == .phone || Layout.device == .pad }
    static var libraryTabs: Int { phone ? 3 : SidebarPlan.maxLibraryTabs }

    /// The places, in order (libraries most used first).
    private struct Place: Identifiable { let id: String; let title: String; let icon: String }

    private var places: [Place] {
        var out = [Place(id: "home", title: "Home", icon: "house")]
        for entry in plan.entries {
            switch entry {
            case .library(let view): out.append(Place(id: view.id, title: view.name ?? "Library", icon: icon(for: view)))
            case .audiobooks: out.append(Place(id: "audiobooks", title: "Audiobooks", icon: "headphones"))
            case .more: out.append(Place(id: "more", title: "More", icon: "square.grid.2x2"))
            }
        }
        if app.downloads != nil && !Self.placesInMenu { out.append(Place(id: "downloads", title: "Downloads", icon: "arrow.down.circle")) }
        out.append(Place(id: "search", title: "Search", icon: "magnifyingglass"))
        if !Self.placesInMenu { out.append(Place(id: "settings", title: "Settings", icon: "gearshape")) }
        return out
    }

    private func page(for id: String) -> some View {
        PlacePage(id: id, plan: plan).equatable()
    }

    #if os(macOS)
    /// The Mac: the places as a segmented control in the window toolbar,
    /// and the page filling the window. Every place visited stays built,
    /// shown or hidden, under one stack whose path is kept per place.
    private var macShell: some View {
        RoutedStack(path: Binding(get: { paths[selection] ?? [] }, set: { paths[selection] = $0 })) {
            ZStack {
                ForEach(places.filter { visited.contains($0.id) }) { place in
                    let shown = place.id == selection
                    page(for: place.id)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .accessibilityHidden(!shown)
                        .zIndex(shown ? 1 : 0)
                }
            }
        }
        // Outside the stack, so pushed pages keep them; once for the window
        // (per page, every switch rebuilt the toolbar).
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Go to", selection: $selection) {
                    // Words for every place: a segmented control mixing icon-only
                    // and text segments drew icons beside the wrong words.
                    ForEach(places) { place in Text(place.title).tag(place.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("places")
            }
        }
        .profileToolbar(app)
        .frame(minWidth: 640, idealWidth: 1100, maxWidth: .infinity)
        .onAppear {
            visited.insert(selection)
            if paths.isEmpty { paths["home"] = app.launchRoute }
        }
        .onChange(of: selection) { _, tab in
            visited.insert(tab)
            recordOpen(tab)
        }
        .onChange(of: app.pendingTab) { _, tab in
            guard let tab else { return }
            go(to: tab)
            app.pendingTab = nil
        }
        .task { await loadLibraries() }
        .onChange(of: app.settings.hiddenLibraries) { _, _ in reapply() }
        .task { await tabSwitchTest() }
    }
    #endif

    /// Asked to go to a place: its tab, or (one the iPhone keeps in the
    /// profile menu) its page.
    private func go(to tab: String) {
        if places.contains(where: { $0.id == tab }) {
            selection = tab
        } else if tab == "downloads" {
            app.pendingRoute = .downloads
        } else if tab == "settings" {
            app.pendingRoute = .settings("root")
        }
    }


    private func recordOpen(_ tab: String) {
        // Opening a library counts toward its place in the order.
        if tab == "audiobooks" {
            for lib in app.libraries where lib.collectionType == "books" { app.libraryUsage.record(lib.id, weight: LibraryUsage.openWeight) }
        } else if app.libraries.contains(where: { $0.id == tab }) {
            app.libraryUsage.record(tab, weight: LibraryUsage.openWeight)
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            // Every page through `page(for:)`: switching tabs re-renders this
            // view, and only an equatable page stops that reaching every page.
            Tab("Home", systemImage: "house", value: "home") { tab("home") { page(for: "home") } }
            ForEach(Array(plan.entries.enumerated()), id: \.offset) { _, entry in
                if case .library(let view) = entry {
                    Tab(view.name ?? "Library", systemImage: icon(for: view), value: view.id) { tab(view.id) { page(for: view.id) } }
                } else if case .audiobooks = entry {
                    Tab("Audiobooks", systemImage: "headphones", value: "audiobooks") { tab("audiobooks") { page(for: "audiobooks") } }
                } else if case .more = entry {
                    Tab("More", systemImage: "square.grid.2x2", value: "more") { tab("more") { page(for: "more") } }
                }
            }
            if app.downloads != nil && !Self.placesInMenu {
                Tab("Downloads", systemImage: "arrow.down.circle", value: "downloads") { tab("downloads") { page(for: "downloads") } }
            }
            Tab("Search", systemImage: "magnifyingglass", value: "search", role: .search) {
                tab("search") { page(for: "search") }
            }
            if !Self.placesInMenu {
                Tab("Settings", systemImage: "gearshape", value: "settings") { tab("settings") { page(for: "settings") } }
            }
            #if os(tvOS)
            // You, at the end of the tab bar: your picture and name, a tab like
            // the others (Left and Right move along to it — a corner beside
            // the bar couldn't be reached sideways: tvOS won't move focus into
            // its tab bar from the page).
            Tab(value: "profile") {
                tab("profile") { ProfileView() }
            } label: {
                Label {
                    Text(session.account.userName)
                } icon: {
                    if let avatar = profileIcon { Image(uiImage: avatar).renderingMode(.original) } else { Image(systemName: "person.crop.circle") }
                }
            }
            .accessibilityIdentifier("profile.avatar")
            #endif
        }
        .tabViewStyle(.tabBarOnly)
        .onChange(of: selection) { _, tab in recordOpen(tab) }
        .onChange(of: app.pendingTab) { _, tab in
            guard let tab else { return }
            go(to: tab)
            app.pendingTab = nil
        }
    }

    /// A tab's page: on the TV the page itself (the stack is around the
    /// tabs), elsewhere in a stack of its own.
    @ViewBuilder
    private func tab<Page: View>(_ id: String, @ViewBuilder _ page: @escaping () -> Page) -> some View {
        #if os(tvOS)
        page().readsPageWidth()
        #else
        RoutedStack(initial: id == "home" ? app.launchRoute : [], active: selection == id) { page() }
        #endif
    }

    private func loadLibraries() async {
        let key = "views-\(session.id)"
        if let cached = await ContentCache.shared.value([BaseItem].self, for: key) { apply(cached) { _ in true } }
        // Retried: launch can be before the network's ready (the Mac's first
        // run asks for local-network access), and the sidebar stayed bare.
        var fresh: [BaseItem]?
        for attempt in 0..<6 where fresh == nil && !Task.isCancelled {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1 << min(attempt, 4))) }
            fresh = try? await session.client.userViews().items
        }
        guard let fresh else { return }
        TraceFile.write("app", "libraries: " + fresh.map { "\($0.name ?? "?") [\($0.collectionType ?? "nil") \($0.id)]" }.joined(separator: " | "))
        // Books libraries without audiobooks (e-books) get no tab.
        var withAudiobooks: Set<String> = []
        for lib in fresh where lib.collectionType == "books" {
            var q = ItemQuery(parentId: lib.id, includeItemTypes: [.audioBook], limit: 1)
            q.fields = []
            if let page = try? await session.client.items(q), page.totalRecordCount > 0 || !page.items.isEmpty { withAudiobooks.insert(lib.id) }
        }
        audiobookLibraries = withAudiobooks
        apply(fresh) { withAudiobooks.contains($0.id) }
        await ContentCache.shared.store(fresh, for: key)
    }

    private func apply(_ views: [BaseItem], hasAudiobooks: (BaseItem) -> Bool) {
        // Most used first (Movies and TV Shows until there's history).
        let views = app.libraryUsage.ordered(views)
        app.libraries = views
        let next = SidebarPlan(views: views, maxTabs: Self.libraryTabs, hidden: app.settings.hiddenLibraries, hasAudiobooks: hasAudiobooks)
        if next != plan { plan = next }
        app.libraryPlan = next
        app.collectionLibraries = next.collections
    }

    /// A library shown or hidden in Settings: the tabs again, at once.
    private func reapply() {
        guard !app.libraries.isEmpty else { return }
        let books = audiobookLibraries
        apply(app.libraries) { books?.contains($0.id) ?? true }
    }

    /// Icons of a weight: tab bars fill them, and a filled TV or folder is a
    /// solid slab beside an open film strip (TV Shows looked lit).
    private func icon(for view: BaseItem) -> String {
        switch view.collectionType {
        case "movies": "film"
        case "tvshows": "play.tv"
        case "boxsets": "square.stack"
        case "music": "music.note"
        case "books": "books.vertical"
        case "homevideos": "video"
        default: "film.stack"
        }
    }
}

extension View {
    /// The profile corner on every page's navigation bar (iPhone, iPad); the
    /// Mac's window has one toolbar for all its pages, set around the tabs.
    @ViewBuilder func pageToolbar(_ app: AppModel) -> some View {
        #if os(macOS)
        self
        #else
        profileToolbar(app)
        #endif
    }
}

#if os(tvOS)
/// The tab bar's picture of you: your Jellyfin picture (else your initials),
/// round, as an image the tab bar draws as it is (not as a template).
@MainActor
enum ProfileIcon {
    static let size: CGFloat = 40

    static func make(session: UserSession) async -> UIImage? {
        let account = session.account
        let scale: CGFloat = 2
        var picture: CGImage?
        if let tag = account.imageTag {
            let px = Int(size * scale)
            let request = ImageRequest(url: session.client.userImageURL(userId: account.userId, tag: tag, size: px), maxPixelSize: px)
            picture = try? await ImagePipeline.shared.image(for: request)
        }
        let view = ZStack {
            Monogram(account.userName, size: size)
            if let picture { Image(decorative: picture, scale: scale).resizable().scaledToFill() }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
    }
}
#endif

/// One place's page. Equatable (on what it shows), so a parent re-rendering
/// — a tab switch — doesn't re-run its body: pages read the environment,
/// which SwiftUI can't compare, so without this every page and everything
/// in it was re-evaluated on every switch (~80 ms on the Mac).
struct PlacePage: View, Equatable {
    let id: String
    let plan: SidebarPlan

    nonisolated static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.plan == b.plan }

    var body: some View {
        switch id {
        case "home": HomeView()
        case "search": SearchView()
        case "downloads": DownloadsView()
        case "settings": SettingsView()
        default:
            ForEach(Array(plan.entries.enumerated()), id: \.offset) { _, entry in
                if case .library(let view) = entry, view.id == id { LibraryView(library: view) }
                else if case .audiobooks(let libraries) = entry, id == "audiobooks" { AudiobookLibraryView(libraries: libraries) }
                else if case .more(let libraries) = entry, id == "more" { MoreLibrariesView(libraries: libraries) }
            }
        }
    }
}

/// A NavigationStack that owns its path and exposes `\.navigate` so any
/// descendant (a card deep inside a shelf) can push a route.
struct RoutedStack<Root: View>: View {
    @State private var ownPath: [Route]
    /// A path kept by the caller instead (the Mac's, one per place).
    private let external: Binding<[Route]>?
    @State private var lastPush: ContinuousClock.Instant?
    /// The stack routes from outside any page (`app.pendingRoute`) land in:
    /// with a stack per tab, the selected tab's.
    let active: Bool
    let root: () -> Root

    init(initial: [Route] = [], active: Bool = true, @ViewBuilder root: @escaping () -> Root) {
        _ownPath = State(initialValue: initial)
        external = nil
        self.active = active
        self.root = root
    }

    init(path: Binding<[Route]>, @ViewBuilder root: @escaping () -> Root) {
        _ownPath = State(initialValue: [])
        external = path
        active = true
        self.root = root
    }

    private var path: Binding<[Route]> { external ?? $ownPath }

    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack(path: path) {
            root()
                .readsPageWidth()
                .pageToolbar(app)
                .navigationDestination(for: Route.self) { route in
                    destination(route).readsPageWidth().pageToolbar(app)
                }
        }
        .environment(\.navigate, NavigateAction { push($0) })
        .onChange(of: app.pendingRoute) { _, route in
            guard active, let route else { return }
            push(route)
            app.pendingRoute = nil
        }
    }

    /// One push per page: a double tap (or a second push mid-animation) is
    /// dropped — the same page twice in a row is never what was meant, and
    /// SwiftUI's navigation has crashed on a path changing under it.
    private func push(_ route: Route) {
        if path.wrappedValue.last == route { return }
        if let last = lastPush, ContinuousClock.now - last < .milliseconds(450) { return }
        lastPush = .now
        path.wrappedValue.append(route)
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .item(let item): ItemDetailView(item: item)
        case .library(let library):
            if library.collectionType == "books" { AudiobookLibraryView(libraries: [library]) } else { LibraryView(library: library) }
        case .grid(let spec): CollectionPage(spec: spec)
        case .profile: ProfileView()
        case .audiobook(let id): AudiobookDetailView(bookId: id)
        case .queue: QueuePage()
        case .downloads: DownloadsView()
        case .downloadedShow(let id): DownloadedShowView(seriesId: id)
        case .settings(let page):
            switch page {
            case "themes": ThemesView()
            case "capabilities": CapabilitiesView()
            #if DEBUG
            case "budgets": BudgetsView()
            #endif
            // Everything else is a section of the one Settings page.
            default: SettingsView(start: page == "root" ? nil : page)
            }
        }
    }
}

