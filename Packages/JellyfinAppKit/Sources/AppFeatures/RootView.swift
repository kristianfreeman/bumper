#if os(tvOS)
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

    public init() {}

    public var body: some View {
        RootView()
            .environment(app)
            .environment(app.settings)
            .environment(app.themes)
            .environment(\.theme, app.themes.theme)
            .environment(\.jellyfin, app.session?.client)
            .environment(\.hideSpoilers, app.settings.hideSpoilers)
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
                    .fullScreenCover(isPresented: $app.showsAudiobook) {
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
            if phase != .active { PerfRecorder.shared.writeSession() }
        }
        .fullScreenCover(item: $app.playback) { request in
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
    case tonight
}

nonisolated struct GridSpec: Hashable, Sendable {
    var title: String
    var filter: CollectionFilter

    init(title: String, query: ItemQuery, library: String) {
        self.title = title
        filter = CollectionFilter(base: query, libraryName: library)
    }

    init(title: String, filter: CollectionFilter) {
        self.title = title
        self.filter = filter
    }
}

/// BUMPER at the top of the sidebar, not selectable (tvOS 27: there's no
/// sidebar header before it, and a fake tab would count toward the seven).
private struct SidebarBrandHeader: ViewModifier {
    func body(content: Content) -> some View {
        if #available(tvOS 27.0, *) {
            content.tabViewSidebarHeader { SidebarMark() }
        } else {
            content
        }
    }
}

/// The word where it fits, the sticker where it doesn't (the collapsed
/// icon column): still, 38 pt tall, on the sidebar's leading inset.
private struct SidebarMark: View {
    @State private var width: CGFloat = 300

    var body: some View {
        BrandMark(width < 120 ? .symbol : .wordmark, height: 38, still: true)
            .frame(maxWidth: .infinity, alignment: width < 120 ? .center : .leading)
            .padding(.horizontal, width < 120 ? 0 : 20)
            .padding(.vertical, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .focusable(false)
            .accessibilityIdentifier("sidebar.brand")
    }
}

struct MainTabView: View {
    let session: UserSession
    @Environment(AppModel.self) private var app
    @State private var plan = SidebarPlan(views: [], hasAudiobooks: { _ in false })
    @State private var selection = "home"

    init(session: UserSession, initialTab: String? = nil) {
        self.session = session
        _selection = State(initialValue: initialTab ?? "home")
    }

    var body: some View {
        // One stack *around* the tabs, not one per tab: pushed pages cover
        // the whole screen (like the TV app), and the sidebarAdaptable tab
        // view can't clip their top edge — it does that to pages pushed
        // inside a tab, leaving a strip of the root page showing through.
        RoutedStack(initial: app.launchRoute) {
            TabView(selection: $selection) {
                Tab("Home", systemImage: "house", value: "home") {
                    HomeView()
                }
                // At most four library tabs: past seven entries the sidebar
                // stops opening (see SidebarPlan).
                ForEach(Array(plan.entries.enumerated()), id: \.offset) { _, entry in
                    if case .library(let view) = entry {
                        Tab(view.name ?? "Library", systemImage: icon(for: view), value: view.id) { LibraryView(library: view) }
                    } else if case .audiobooks(let libraries) = entry {
                        Tab("Audiobooks", systemImage: "headphones", value: "audiobooks") { AudiobookLibraryView(libraries: libraries) }
                    } else if case .more(let libraries) = entry {
                        Tab("More", systemImage: "square.grid.2x2", value: "more") { MoreLibrariesView(libraries: libraries) }
                    }
                }
                Tab("Search", systemImage: "magnifyingglass", value: "search", role: .search) {
                    SearchView()
                }
                Tab("Settings", systemImage: "gearshape", value: "settings") {
                    SettingsView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .onChange(of: selection) { _, tab in
                // Opening a library counts toward its place in the order.
                if tab == "audiobooks" {
                    for lib in app.libraries where lib.collectionType == "books" { app.libraryUsage.record(lib.id, weight: LibraryUsage.openWeight) }
                } else if app.libraries.contains(where: { $0.id == tab }) {
                    app.libraryUsage.record(tab, weight: LibraryUsage.openWeight)
                }
            }
            .onChange(of: app.pendingTab) { _, tab in
                guard let tab else { return }
                selection = tab
                app.pendingTab = nil
            }
            .modifier(SidebarBrandHeader())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await loadLibraries() }
    }

    private func loadLibraries() async {
        let key = "views-\(session.id)"
        if let cached = await ContentCache.shared.value([BaseItem].self, for: key) { apply(cached) { _ in true } }
        guard let fresh = try? await session.client.userViews().items else { return }
        TraceFile.write("app", "libraries: " + fresh.map { "\($0.name ?? "?") [\($0.collectionType ?? "nil")]" }.joined(separator: " | "))
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

/// A NavigationStack that owns its path and exposes `\.navigate` so any
/// descendant (a card deep inside a shelf) can push a route.
struct RoutedStack<Root: View>: View {
    @State private var path: [Route]
    let root: () -> Root

    init(initial: [Route] = [], @ViewBuilder root: @escaping () -> Root) {
        _path = State(initialValue: initial)
        self.root = root
    }

    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .item(let item): ItemDetailView(item: item)
                    case .library(let library):
                        if library.collectionType == "books" { AudiobookLibraryView(libraries: [library]) } else { LibraryView(library: library) }
                    case .grid(let spec): CollectionPage(spec: spec)
                    case .profile: ProfileView()
                    case .audiobook(let id): AudiobookDetailView(bookId: id)
                    case .tonight: TonightPage()
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
        .environment(\.navigate, NavigateAction { path.append($0) })
        .onChange(of: app.pendingRoute) { _, route in
            guard let route else { return }
            path.append(route)
            app.pendingRoute = nil
        }
    }
}
#endif
