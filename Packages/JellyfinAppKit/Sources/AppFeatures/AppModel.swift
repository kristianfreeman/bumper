import AppCore
import AVFoundation
import DesignSystem
import Foundation
import Instrumentation
import JellyfinAPI
import JellyfinMocks
import Observation
import PlaybackCore
import VLCPlayback
import os
import Synchronization
import TopShelf

/// Process-start reference for the launch → first-content metric.
nonisolated enum LaunchClock {
    nonisolated(unsafe) static var start = ContinuousClock.now
    nonisolated(unsafe) static var recorded = false

    static func markFirstContent() {
        guard !recorded else { return }
        recorded = true
        let elapsed = start.duration(to: .now)
        Metrics.shared.record(.launchToFirstContent, elapsed)
        Perf.event("launch.firstContent", "\(elapsed.milliseconds) ms")
        PerfRecorder.shared.writeIfChanged()
    }
}

nonisolated struct PlaybackRequest: Identifiable, Sendable {
    let id = UUID()
    var item: BaseItem
    var resume: Bool
    var mediaSourceId: String?
    var audioIndex: Int?
    var subtitleIndex: Int?
    /// Background Noise: plays on and on (next episode, then back to the
    /// first) and tells the server nothing — nothing marked watched, no
    /// resume points, Continue Watching and Next Up untouched.
    var background = false
}

/// Launch configuration, parsed once from the process arguments.
nonisolated struct LaunchOptions: Sendable {
    /// Talk to the in-process mock server instead of a real one.
    var mock = false
    /// Always show the performance HUD (UI tests read metrics from it).
    var perfHUD = false
    /// Start from a clean slate (no saved servers, no caches).
    var reset = false
    /// Scale for mock server latency (UI tests can simulate slow servers).
    var mockLatencyMs: Int?
    /// Directory of real media (+ manifest.json) the mock server streams.
    var mockMedia: String?
    /// Or a `mock-media-server` on another machine (real Apple TV runs).
    var mockMediaURL: URL?
    /// `-mockBooksURL <url>`: audiobooks served by another machine (device tests).
    var mockBooksURL: URL?
    /// Item id to start playing immediately (perf tests / engine validation).
    var autoplay: String?
    /// Self-driven scroll benchmark (no XCUITest overhead in the numbers).
    var benchmark = false
    /// Deep link for tests: `item:<id>` or `grid:<libraryId>`.
    var route: String?
    /// Serve the mock over a real loopback socket (needed for AVPlayer).
    var mockHTTP = false
    /// `-mock -mockOnboarding`: start signed out, with the mock server listed (onboarding tests).
    var mockOnboarding = false
    /// Start a sleep timer of this many seconds (tests).
    var sleepAfterSeconds: Int?
    /// Run the seek benchmark once playback starts (scripts/seek-bench.sh).
    var seekBench = false
    /// Don't prepare playback on Play focus (before/after measurements).
    var noPrepare = false
    /// Delay `-autoplay` by this many seconds (lets a `-route item:` detail
    /// page prepare first — the "focus Play, then press" path).
    var autoplayAfterSeconds: Double?
    /// `-startAt <s>`: autoplay resumes from here (a stand-in resume point).
    var startAtSeconds: Double?
    /// Names the benchmark's result file (seekbench-<tag>.json), so a device
    /// run can't pick up an earlier run's result.
    var benchTag: String?
    /// Simulated server latency for media requests (-mockHTTP).
    var mediaLatencyMs: Int?
    /// Stand-in HDMI mode switch duration (ms) for measuring overlap in the simulator.
    var simulateModeSwitchMs: Int?
    /// Pretend to be another Apple TV model (e.g. AppleTV6,2) for capability rules.
    var simulateModel: String?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        mock = arguments.contains("-mock")
        perfHUD = arguments.contains("-perfHUD")
        reset = arguments.contains("-reset")
        benchmark = arguments.contains("-benchmark")
        mockHTTP = arguments.contains("-mockHTTP")
        mockOnboarding = arguments.contains("-mockOnboarding")
        if let i = arguments.firstIndex(of: "-simulateModel"), i + 1 < arguments.count { simulateModel = arguments[i + 1] }
        if let i = arguments.firstIndex(of: "-simulateModeSwitch"), i + 1 < arguments.count { simulateModeSwitchMs = Int(arguments[i + 1]) }
        if let i = arguments.firstIndex(of: "-route"), i + 1 < arguments.count { route = arguments[i + 1] }
        if let i = arguments.firstIndex(of: "-mockLatency"), i + 1 < arguments.count { mockLatencyMs = Int(arguments[i + 1]) }
        if let i = arguments.firstIndex(of: "-mockMedia"), i + 1 < arguments.count { mockMedia = arguments[i + 1] }
        if let i = arguments.firstIndex(of: "-mockMediaURL"), i + 1 < arguments.count { mockMediaURL = URL(string: arguments[i + 1]) }
        if let i = arguments.firstIndex(of: "-mockBooksURL"), i + 1 < arguments.count { mockBooksURL = URL(string: arguments[i + 1]) }
        if let i = arguments.firstIndex(of: "-sleepAfter"), i + 1 < arguments.count { sleepAfterSeconds = Int(arguments[i + 1]) }
        seekBench = arguments.contains("-seekBench")
        noPrepare = arguments.contains("-noPrepare")
        if let i = arguments.firstIndex(of: "-autoplayAfter"), i + 1 < arguments.count { autoplayAfterSeconds = Double(arguments[i + 1]) }
        if let i = arguments.firstIndex(of: "-startAt"), i + 1 < arguments.count { startAtSeconds = Double(arguments[i + 1]) }
        if let i = arguments.firstIndex(of: "-benchTag"), i + 1 < arguments.count { benchTag = arguments[i + 1] }
        if let i = arguments.firstIndex(of: "-mediaLatency"), i + 1 < arguments.count { mediaLatencyMs = Int(arguments[i + 1]) }
        if let i = arguments.firstIndex(of: "-autoplay"), i + 1 < arguments.count { autoplay = arguments[i + 1] }
    }
}

@MainActor
@Observable
final class AppModel {
    let options: LaunchOptions
    let settings: AppSettings
    let accounts: AccountStore
    let themes: ThemeStore
    let sleepTimer = SleepTimer()
    /// Which libraries get used most (orders the sidebar, Home and the Top Shelf).
    let libraryUsage: LibraryUsage
    /// The server's libraries, most used first (set as the sidebar loads them).
    var libraries: [BaseItem] = []
    /// Words → filters (services/search, falling back to the device's own reading).
    let search = SmartSearch.configured()
    /// Judges which subtitle the server found fits (Jev on the search service, else on the device).
    let subtitleRanker = SubtitleRanker.configured()
    /// The queue (per account).
    let queue = QueueStore()
    /// What's focused anywhere in the app, and what's playing (the companion shows both).
    var focusedItem: BaseItem?
    var nowPlaying: NowPlayingInfo?
    @ObservationIgnored lazy var companion = CompanionBridge(app: self)
    @ObservationIgnored private var defaults: UserDefaults = .standard
    let capabilities: DeviceCapabilities
    private(set) var session: UserSession?
    var playback: PlaybackRequest?
    /// A page (or tab) to open from outside the app (a Top Shelf link).
    var pendingRoute: Route?
    var pendingTab: String?
    /// The audiobook playing (it keeps playing while you browse) and whether
    /// its Now Playing screen is up.
    var audiobook: AudiobookPlayer?
    var showsAudiobook = false
    /// Books by id, filled as libraries load (a card navigates by id).
    @ObservationIgnored var audiobooks: [String: Audiobook] = [:]
    /// Box-set libraries, shown as a Collections row on Movies (no tab).
    @ObservationIgnored var collectionLibraries: [BaseItem] = []

    @ObservationIgnored private var prewarmed: [String: (Task<PlaybackPlan, any Error>, ContinuousClock.Instant)] = [:]
    private static let log = Perf.logger("app")

    init(options: LaunchOptions = LaunchOptions()) {
        self.options = options
        let built = (Bundle.main.executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date })
            .map { $0.formatted(.iso8601) } ?? "?"
        TraceFile.write("app", "launch \(PerfRecorder.deviceModel) build \(built) args: \(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
        let defaults = options.mock ? UserDefaults(suiteName: "mock")! : .standard
        if options.reset {
            defaults.removePersistentDomain(forName: options.mock ? "mock" : Brand.bundleIdentifier)
            Task { await ContentCache.shared.removeAll(); await ImagePipeline.shared.removeAll() }
        }
        let protocols: [AnyClass] = options.mock && !options.mockHTTP ? [MockJellyfinProtocol.self] : []
        if options.mock || options.mockHTTP {
            ImagePipeline.shared.configure(protocolClasses: protocols)
            if let ms = options.mockLatencyMs { MockJellyfinProtocol.latency.withLock { $0 = .milliseconds(ms) } }
            if let base = options.mockBooksURL {
                do { try MockBooks.configure(remote: base) } catch { TraceFile.write("app", "mock books at \(base.absoluteString) failed: \(error)") }
            }
            if let base = options.mockMediaURL {
                do {
                    try MockMedia.configure(remote: base)
                    TraceFile.write("app", "mock media at \(base.absoluteString)")
                } catch {
                    TraceFile.write("app", "mock media at \(base.absoluteString) failed: \(error)")
                }
            } else if let dir = options.mockMedia {
                MockMedia.configure(directory: URL(filePath: dir))
            }
        }
        settings = AppSettings(defaults: defaults)
        libraryUsage = LibraryUsage(defaults: defaults)
        accounts = AccountStore(defaults: defaults, keychain: Keychain(service: Brand.bundleIdentifier + (options.mock ? ".mock" : "")), protocolClasses: protocols)
        themes = ThemeStore(settings: settings)
        capabilities = Perf.measureSync("capabilities.probe", "launch.capabilities") { DeviceCapabilities.probe() }

        session = accounts.restoreActiveSession()
        if options.mockHTTP, let url = Self.startMockServer() {
            // Fresh session every launch: the loopback URL is what AVPlayer sees.
            let server = ServerRecord(id: "mock-server", name: "Mock Jellyfin (HTTP)", url: url, version: "10.11.11")
            session = accounts.signIn(server: server, result: MockJellyfinProtocol.authenticationResult)
        } else if options.mock && options.mockOnboarding {
            accounts.upsert(server: ServerRecord(id: "mock-server", name: "Mock Jellyfin", url: MockJellyfinProtocol.baseURL, version: "10.11.11"))
            session = nil
        } else if options.mock && session?.server.url != MockJellyfinProtocol.baseURL {
            // Includes a session left over from a -mockHTTP run, whose loopback
            // server died with that process.
            let server = ServerRecord(id: "mock-server", name: "Mock Jellyfin", url: MockJellyfinProtocol.baseURL, version: "10.11.11")
            session = accounts.signIn(server: server, result: MockJellyfinProtocol.authenticationResult)
        }
        Self.configureAudioSession()
        InputTrace.install()
        if let session { queue.attach(account: session.id, sleepTimer: sleepTimer, defaults: defaults) }
        self.defaults = defaults
        FocusTracker.onFeatured = { [weak self] item in self?.focusedItem = item }
        companion.start()
        if ProcessInfo.processInfo.arguments.contains("-metricsFile") {
            // Device runs (scripts/device-scroll-check.sh): frame timing to a
            // file every second, read back with devicectl.
            HitchMonitor.shared.start()
            Task { @MainActor in
                let url = PerfRecorder.shared.latestURL.deletingLastPathComponent().appending(path: "metrics.json")
                while true {
                    try? await Task.sleep(for: .seconds(1))
                    try? Metrics.shared.snapshotJSON().write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
        if let ms = options.simulateModeSwitchMs { DisplayModeManager.simulatedSwitch = .milliseconds(ms) }
        if let s = options.sleepAfterSeconds { sleepTimer.set(seconds: s) }
        if let ms = options.mediaLatencyMs { MockMedia.latency.withLock { $0 = .milliseconds(ms) } }
        if let session { reportCapabilities(session) }
        if let id = options.autoplay {
            TraceFile.write("app", "autoplay \(id): session \(session.map { $0.server.url.absoluteString } ?? "none")")
            if let client = session?.client {
                Task {
                    if let delay = options.autoplayAfterSeconds { try? await Task.sleep(for: .seconds(delay)) }
                    do {
                        var item = try await client.item(id: id)
                        if item.kind == .audioBook || item.kind == .folder, let book = await self.audiobook(id: id) {
                            self.listen(book, from: options.startAtSeconds)
                            return
                        }
                        if let start = options.startAtSeconds {
                            if item.userData == nil { item.userData = UserItemData() }
                            item.userData?.playbackPositionTicks = Duration.seconds(start).ticks
                        }
                        // Delayed autoplay stands in for pressing the Play button (which resumes).
                        self.play(item, resume: options.autoplayAfterSeconds != nil || options.startAtSeconds != nil)
                    } catch {
                        TraceFile.write("app", "autoplay \(id) failed: \(error)")
                    }
                }
            }
        }
    }

    /// The previous app instance may still be releasing :8097 when we launch
    /// (tests relaunch back to back), so retry briefly before giving up.
    private static func startMockServer() -> URL? {
        for attempt in 1...20 {
            do { return try MockHTTPServer.shared.start(port: 8097) } catch {
                if attempt == 20 {
                    log.error("Mock HTTP server failed to start: \(error.localizedDescription, privacy: .public)")
                    TraceFile.write("app", "mock HTTP server failed: \(error.localizedDescription)")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        return nil
    }

    /// Movie playback mode + multichannel output so
    /// 5.1/7.1/Atmos reach the receiver.
    private static func configureAudioSession() {
        #if !os(macOS)                                   // the Mac has no audio session
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .moviePlayback)
        try? audio.setSupportsMultichannelContent(true)
        try? audio.setActive(true)
        #endif
    }

    var planner: PlaybackPlanner {
        let budget = SoftwareDecodeBudget.forModel(options.simulateModel ?? PerfRecorder.hardwareModel)
        return PlaybackPlanner(
            capabilities: capabilities, preference: settings.enginePreference, maxBitrate: settings.maxBitrate,
            softwareDecodeCheck: { codec, w, h, fps in budget.allows(codec: codec, pixelRate: Double(w * h) * fps) }
        )
    }

    // MARK: Session

    func didSignIn(_ session: UserSession) {
        self.session = session
        queue.attach(account: session.id, sleepTimer: sleepTimer, defaults: defaults)
        reportCapabilities(session)
    }

    func signOut() {
        guard let session else { return }
        let client = session.client
        Task { try? await client.logout() }
        accounts.signOut(session.account.id)
        self.session = nil
        Task { await ContentCache.shared.removeAll() }
    }

    /// Cycles to the next saved account (the profile menu's Switch User).
    func switchToNextAccount() {
        let all = accounts.accounts
        guard all.count > 1, let i = all.firstIndex(where: { $0.id == session?.id }) else { return }
        switchAccount(all[(i + 1) % all.count].id)
    }

    func switchAccount(_ id: String) {
        session = accounts.switchTo(id)
    }

    /// The setting, or forced on for this launch only (-perfHUD/-benchmark;
    /// never saved, so a test run doesn't leave the HUD on afterwards).
    var showsPerformanceHUD: Bool { settings.showPerformanceHUD || options.perfHUD || options.benchmark }

    private func reportCapabilities(_ session: UserSession) {
        let profile = planner.deviceProfile()
        Task.detached { try? await session.client.reportCapabilities(deviceProfile: profile) }
    }

    /// Initial navigation stack for the Home tab from `-route`.
    var launchRoute: [Route] {
        guard let route = options.route else { return [] }
        if route == "queue" { return [.queue] }
        let parts = route.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        switch parts[0] {
        case "item": return [.item(BaseItem(id: parts[1], name: nil, kind: .movie))]
        case "library":
            var lib = BaseItem(id: parts[1], name: "Movies", kind: .collectionFolder)
            lib.collectionType = "movies"
            return [.library(lib)]
        case "books":
            var lib = BaseItem(id: parts[1], name: "Audiobooks", kind: .collectionFolder)
            lib.collectionType = "books"
            return [.library(lib)]
        case "audiobook": return [.audiobook(parts[1])]
        case "queue": return [.queue]
        case "settings": return [.settings(parts[1])]
        case "profile": return [.profile]
        case "grid":
            var q = ItemQuery(parentId: parts[1], includeItemTypes: [.movie])
            q.limit = 100
            return [.grid(GridSpec(title: "All Movies", query: q, library: "Movies"))]
        default: return []
        }
    }

    /// `bumper://play/<id>` plays it (resuming), `bumper://item/<id>` opens its page.
    func open(_ url: URL) {
        TraceFile.write("app", "open \(url.absoluteString)")
        guard let link = TopShelfSnapshot.Link(url), let client = session?.client else { return }
        Task {
            switch link {
            case .play(let id):
                if let item = try? await client.item(id: id) { play(item) }
            case .item(let id):
                if let item = try? await client.item(id: id) { pendingRoute = .item(item) }
            case .library(let id):
                if let library = try? await client.item(id: id) { pendingRoute = .library(library) }
            case .queue:
                pendingRoute = .queue
            case .search:
                pendingTab = "search"
            }
        }
    }

    // MARK: Playback

    /// Background Noise: a show from a random episode (or this episode, or
    /// this film), on a loop, without marking anything watched.
    func playInBackground(_ item: BaseItem) {
        guard let client = session?.client else { return }
        TraceFile.write("player", "background: \(item.name ?? item.id)")
        Task {
            var start = item
            if item.kind == .series, let eps = try? await client.episodes(seriesId: item.id, seasonId: nil).items, let pick = eps.randomElement() {
                start = pick
            }
            if audiobook != nil { stopAudiobook() }
            playback = PlaybackRequest(item: start, resume: false, background: true)
        }
    }

    /// Start (or resume) a book and show its Now Playing screen.
    func listen(_ book: Audiobook, from start: Double? = nil) {
        guard let client = session?.client else { return }
        if let lib = libraries.first(where: { $0.collectionType == "books" }) { libraryUsage.record(lib.id, weight: LibraryUsage.playWeight) }
        if audiobook?.book.id == book.id, start == nil {
            showsAudiobook = true
            return
        }
        audiobook?.stop()
        let player = AudiobookPlayer(book: book, client: client, settings: settings, sleepTimer: sleepTimer)
        audiobook = player
        player.start(at: start ?? book.resumePosition ?? 0)
        showsAudiobook = true
    }

    func stopAudiobook() {
        audiobook?.stop()
        audiobook = nil
        showsAudiobook = false
    }

    /// A book by id: from a loaded library, else from the server (a file, or
    /// a folder of files).
    func audiobook(id: String) async -> Audiobook? {
        if let book = audiobooks[id] { return book }
        guard let client = session?.client, let item = try? await client.item(id: id) else { return nil }
        if item.kind == .audioBook { return Audiobook.book(id: id, parts: [item]) }
        var q = ItemQuery(parentId: id, includeItemTypes: [.audioBook], sortBy: ["IndexNumber", "SortName"])
        q.fields = ItemField.card + [.chapters, .overview]
        guard let parts = try? await client.items(q).items, !parts.isEmpty else { return nil }
        let book = Audiobook.book(id: id, parts: parts)
        audiobooks[id] = book
        return book
    }

    func play(_ item: BaseItem, resume: Bool = true, mediaSourceId: String? = nil, audioIndex: Int? = nil, subtitleIndex: Int? = nil) {
        if audiobook != nil { stopAudiobook() }             // one thing plays at a time
        libraryUsage.recordPlay(item, libraries: libraries)
        playback = PlaybackRequest(item: item, resume: resume, mediaSourceId: mediaSourceId, audioIndex: audioIndex, subtitleIndex: subtitleIndex)
    }

    /// Fires PlaybackInfo as soon as a Play button *gets focus*, so by the time
    /// the user clicks, the server round trip is already done. Plans are reused
    /// for 60 s.
    func prewarm(_ item: BaseItem) {
        guard let session, item.kind.isPlayable else { return }
        if let existing = prewarmed[item.id], existing.1.duration(to: .now) < .seconds(60) { return }
        let planner = planner
        let start = item.resumePosition
        let task = Task { try await planner.plan(item: item, client: session.client, startPosition: start) }
        prewarmed[item.id] = (task, .now)
    }

    // MARK: Prepared playback

    /// One item opened and buffered ahead of the press, paused on its first
    /// frame: Play then just starts it.
    @ObservationIgnored private var prepared: (itemId: String, plan: PlaybackPlan, engine: any PlayerEngine)?
    @ObservationIgnored private var preparing: (itemId: String, task: Task<Void, Never>)?

    func makeEngine(_ kind: EngineKind) -> any PlayerEngine {
        switch kind {
        case .native: NativeEngine()
        case .vlc: VLCEngine(subtitleStyle: VLCSubtitleStyle(settings.subtitleStyle, scale: settings.subtitleScale, font: settings.subtitleFont))
        }
    }

    /// The detail page's Play button has focus — the strongest "about to
    /// press Play" signal there is. Plans that one item and, if it's a VLCKit
    /// item, opens and buffers it.
    func prepare(_ item: BaseItem) {
        guard !options.noPrepare, item.kind.isPlayable, playback == nil,
              prepared?.itemId != item.id, preparing?.itemId != item.id else { return }
        releasePrepared()
        prewarm(item)
        guard let planTask = prewarmed[item.id]?.0 else { return }
        let id = item.id
        let task = Task { [weak self] in
            guard let plan = try? await planTask.value, let self, !Task.isCancelled else { return }
            // Measured on an Apple TV 4K: preparing makes VLCKit start in
            // ~0.18 s instead of 0.3–0.7 s; AVPlayer starts in ~0.45 s either
            // way, so for it the prefetched plan is all that's worth holding.
            guard plan.engine == .vlc else { self.preparing = nil; return }
            let engine = self.makeEngine(plan.engine)
            do { try await engine.load(plan, autoplay: false) } catch { engine.stop(); return }
            guard !Task.isCancelled, self.preparing?.itemId == id else { engine.stop(); return }
            self.prepared = (id, plan, engine)
            self.preparing = nil
            TraceFile.write("app", "prepared \(id) on \(plan.engine.rawValue)")
            try? await Task.sleep(for: .seconds(60))          // never hold a paused stream for long
            if self.prepared?.itemId == id, self.playback == nil { self.releasePrepared() }
        }
        preparing = (id, task)
    }

    func releasePrepared() {
        preparing?.task.cancel()
        preparing = nil
        prepared?.engine.stop()
        prepared = nil
    }

    /// The prepared backend for this request, if it's the same item with no
    /// track/version overrides (waits if preparation is still in flight).
    func takePrepared(for request: PlaybackRequest) async -> (plan: PlaybackPlan, engine: any PlayerEngine)? {
        guard request.resume, request.mediaSourceId == nil, request.audioIndex == nil, request.subtitleIndex == nil else { return nil }
        if let inFlight = preparing, inFlight.itemId == request.item.id { await inFlight.task.value }
        guard let p = prepared, p.itemId == request.item.id else { return nil }
        prepared = nil
        return (p.plan, p.engine)
    }

    func takePrewarmedPlan(for request: PlaybackRequest) -> Task<PlaybackPlan, any Error>? {
        guard request.resume, request.mediaSourceId == nil, request.audioIndex == nil, request.subtitleIndex == nil,
              let entry = prewarmed.removeValue(forKey: request.item.id), entry.1.duration(to: .now) < .seconds(60) else { return nil }
        return entry.0
    }
}
