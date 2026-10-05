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
    let remoteTab: AnyView?

    /// `remoteTab`: the iPhone/iPad app's Apple TV remote, as a tab of its own.
    public init(remoteTab: AnyView? = nil) { self.remoteTab = remoteTab }

    public var body: some View {
        RootView()
            .environment(\.remoteTab, remoteTab)
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

/// "Bumper" at the top of the sidebar in plain sidebar-title type, not
/// selectable (tvOS 27; there's no sidebar header before it, and a fake tab
/// would count toward the seven). The sidebar's focus leans on there being
/// a header: without one, Menu and Up from the page stopped reaching it.
private struct SidebarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(tvOS 27.0, *) {
            content.tabViewSidebarHeader {
                Text(Brand.displayName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .focusable(false)
                    .accessibilityIdentifier("sidebar.title")
            }
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    @Entry var remoteTab: AnyView? = nil
}

struct MainTabView: View {
    let session: UserSession
    @Environment(AppModel.self) private var app
    @Environment(\.remoteTab) private var remoteTab
    @State private var plan = SidebarPlan(views: [], hasAudiobooks: { _ in false })
    @State private var selection = "home"
    #if os(macOS)
    @State private var columns = NavigationSplitViewVisibility.all
    #endif

    init(session: UserSession, initialTab: String? = nil) {
        self.session = session
        _selection = State(initialValue: initialTab ?? "home")
    }

    var body: some View {
        #if os(macOS)
        macShell
        #else
        tabs
        #endif
    }

    /// The places in the sidebar, in order (libraries most used first).
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
        if app.downloads != nil { out.append(Place(id: "downloads", title: "Downloads", icon: "arrow.down.circle")) }
        out.append(Place(id: "search", title: "Search", icon: "magnifyingglass"))
        out.append(Place(id: "settings", title: "Settings", icon: "gearshape"))
        return out
    }

    @ViewBuilder
    private func page(for id: String) -> some View {
        switch id {
        case "home": HomeView()
        case "search": SearchView()
        case "downloads": DownloadsView()
        case "settings": SettingsView()
        case "remote": remoteTab
        default:
            ForEach(Array(plan.entries.enumerated()), id: \.offset) { _, entry in
                if case .library(let view) = entry, view.id == id { LibraryView(library: view) }
                else if case .audiobooks(let libraries) = entry, id == "audiobooks" { AudiobookLibraryView(libraries: libraries) }
                else if case .more(let libraries) = entry, id == "more" { MoreLibrariesView(libraries: libraries) }
            }
        }
    }

    #if os(macOS)
    /// The Mac's own shape: a sidebar list and the page beside it (the tab
    /// view's adaptable sidebar didn't open there, and laid pages out wider
    /// than the window).
    private var macShell: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: Binding<String?>(get: { selection }, set: { if let s = $0 { selection = s } })) {
                ForEach(places) { place in
                    Label(place.title, systemImage: place.icon).tag(place.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            RoutedStack(initial: selection == "home" ? app.launchRoute : []) { page(for: selection) }
                .id(selection)
                .frame(minWidth: 520, idealWidth: 960, maxWidth: .infinity)
                .navigationSplitViewColumnWidth(min: 520, ideal: 960)
        }
        .onChange(of: selection) { _, tab in recordOpen(tab) }
        .onChange(of: app.pendingTab) { _, tab in
            guard let tab else { return }
            selection = tab
            app.pendingTab = nil
        }
        .task { await loadLibraries() }
        .task {
            // Tests: `-sidebarToggleTest` closes the sidebar and opens it again.
            guard ProcessInfo.processInfo.arguments.contains("-sidebarToggleTest") else { return }
            try? await Task.sleep(for: .seconds(2))
            // Frames while the sidebar closes and opens (the page reflows with it).
            Metrics.shared.reset()
            HitchMonitor.shared.start()
            HitchMonitor.shared.resetTotals()
            for visibility in [NavigationSplitViewVisibility.detailOnly, .all, .detailOnly, .all] {
                withAnimation { columns = visibility }
                for _ in 0..<10 { HitchMonitor.shared.noteActivity(); try? await Task.sleep(for: .milliseconds(100)) }
            }
            Benchmark.traceFrames("sidebar")
        }
    }
    #endif

    private func recordOpen(_ tab: String) {
        // Opening a library counts toward its place in the order.
        if tab == "audiobooks" {
            for lib in app.libraries where lib.collectionType == "books" { app.libraryUsage.record(lib.id, weight: LibraryUsage.openWeight) }
        } else if app.libraries.contains(where: { $0.id == tab }) {
            app.libraryUsage.record(tab, weight: LibraryUsage.openWeight)
        }
    }

    private var tabs: some View {
        // One stack *around* the tabs, not one per tab: pushed pages cover
        // the whole screen (like the TV app), and the sidebarAdaptable tab
        // view can't clip their top edge — it does that to pages pushed
        // inside a tab, leaving a strip of the root page showing through.
        RoutedStack(initial: app.launchRoute) {
            TabView(selection: $selection) {
                Tab("Home", systemImage: "house", value: "home") {
                    HomeView().tabPage()          // each tab its own area (the iPad's sidebar takes some)
                }
                // At most four library tabs: past seven entries the sidebar
                // stops opening (see SidebarPlan).
                ForEach(Array(plan.entries.enumerated()), id: \.offset) { _, entry in
                    if case .library(let view) = entry {
                        Tab(view.name ?? "Library", systemImage: icon(for: view), value: view.id) { LibraryView(library: view).tabPage() }
                    } else if case .audiobooks(let libraries) = entry {
                        Tab("Audiobooks", systemImage: "headphones", value: "audiobooks") { AudiobookLibraryView(libraries: libraries).tabPage() }
                    } else if case .more(let libraries) = entry {
                        Tab("More", systemImage: "square.grid.2x2", value: "more") { MoreLibrariesView(libraries: libraries).tabPage() }
                    }
                }
                if app.downloads != nil {
                    Tab("Downloads", systemImage: "arrow.down.circle", value: "downloads") { DownloadsView().tabPage() }
                }
                if let remoteTab {
                    Tab("Remote", systemImage: "appletvremote.gen4", value: "remote") { remoteTab.tabPage() }
                }
                Tab("Search", systemImage: "magnifyingglass", value: "search", role: .search) {
                    SearchView().tabPage(corner: !Platform.isTV)   // the TV's search keyboard fills the top
                }
                Tab("Settings", systemImage: "gearshape", value: "settings") {
                    SettingsView().tabPage()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .onChange(of: selection) { _, tab in recordOpen(tab) }
            .onChange(of: app.pendingTab) { _, tab in
                guard let tab else { return }
                selection = tab
                app.pendingTab = nil
            }
            .modifier(SidebarTitle())
            .overlay(alignment: .top) {
                if !Platform.isTV && !Platform.isMac {
                    TopBand { ProfileCluster() }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Layout.horizontalMargin)
                        .padding(.top, 4)
                }
            }
            .hidesNavigationBarEntirely()
        }
        .task { await loadLibraries() }
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
        apply(fresh) { withAudiobooks.contains($0.id) }
        await ContentCache.shared.store(fresh, for: key)
    }

    private func apply(_ views: [BaseItem], hasAudiobooks: (BaseItem) -> Bool) {
        // Most used first (Movies and TV Shows until there's history).
        let views = app.libraryUsage.ordered(views)
        app.libraries = views
        let next = SidebarPlan(views: views, hasAudiobooks: hasAudiobooks)
        if next != plan { plan = next }
        app.collectionLibraries = next.collections
    }

    private func icon(for view: BaseItem) -> String {
        switch view.collectionType {
        case "movies": "film"
        case "tvshows": "tv"
        case "boxsets": "square.stack"
        case "music": "music.note"
        case "books": "books.vertical"
        default: "folder"
        }
    }
}

extension View {
    /// A tab's page: its width, and on the TV the profile corner pinned at
    /// its top — part of the page, so focus coming back from the sidebar
    /// lands in the page, not on the corner first. (The iPhone and iPad pin
    /// it over the tab view, in line with the iPad's floating tab bar; the
    /// Mac puts it in its toolbar.)
    func tabPage(corner: Bool = true) -> some View {
        readsPageWidth()
            .overlay(alignment: .top) {
                if corner && Platform.isTV {
                    TopBand { ProfileCluster() }
                        .fixedSize(horizontal: false, vertical: true)   // the TV's focus guide would take the whole height
                        .padding(.horizontal, Layout.horizontalMargin)
                        .padding(.top, Platform.isTV ? 0 : 4)
                        // The TV's pages run under its sideways safe area: line up with them.
                        .ignoresSafeArea(.container, edges: Platform.isTV ? .horizontal : [])
                }
            }
    }
}

/// A NavigationStack that owns its path and exposes `\.navigate` so any
/// descendant (a card deep inside a shelf) can push a route.
struct RoutedStack<Root: View>: View {
    @State private var path: [Route]
    @State private var lastPush: ContinuousClock.Instant?
    let root: () -> Root

    init(initial: [Route] = [], @ViewBuilder root: @escaping () -> Root) {
        _path = State(initialValue: initial)
        self.root = root
    }

    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .readsPageWidth()
                .profileToolbar(app)
                .navigationDestination(for: Route.self) { route in
                    destination(route).readsPageWidth().profileToolbar(app)
                }
        }
        .environment(\.navigate, NavigateAction { push($0) })
        .onChange(of: app.pendingRoute) { _, route in
            guard let route else { return }
            push(route)
            app.pendingRoute = nil
        }
    }

    /// One push per page: a double tap (or a second push mid-animation) is
    /// dropped — the same page twice in a row is never what was meant, and
    /// SwiftUI's navigation has crashed on a path changing under it.
    private func push(_ route: Route) {
        if path.last == route { return }
        if let last = lastPush, ContinuousClock.now - last < .milliseconds(450) { return }
        lastPush = .now
        path.append(route)
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
