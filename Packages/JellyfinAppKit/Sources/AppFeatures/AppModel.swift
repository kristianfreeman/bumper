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
    /// Background: plays on and on (next episode, then back to the first)
    /// and tells the server nothing — nothing marked watched, no
    /// resume points, Continue Watching and Next Up untouched.
    var background = false
    /// A playlist's items after this one, played in turn.
    var sequence: [BaseItem] = []
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
    /// `-autoplayBackground`: autoplay as Background — the server is told
    /// nothing (no progress, nothing marked watched): measuring a real library.
    var autoplayBackground = false
    /// `-autoplaySubtitles ass|bitmap|text`: autoplay with a subtitle of that kind on.
    var autoplaySubtitles: String?
    /// `-libraryMatrix`: one item for each kind of file in the library
    /// (container, codecs, size, scan, range, audio, subtitles), written to
    /// Library/Caches/perf/library-matrix.json for scripts/device-library-matrix.sh.
    var libraryMatrix = false
    /// Self-driven scroll benchmark (no XCUITest overhead in the numbers).
    var benchmark = false
    /// Deep link for tests: `item:<id>`, `person:<id>` or `grid:<libraryId>`.
    var route: String?
    /// Serve the mock over a real loopback socket (needed for AVPlayer).
    var mockHTTP = false
    /// `-mockPort <n>`: that socket's port; 0 is any free one (UI tests
    /// running side by side, each simulator on the Mac's own loopback).
    var mockPort: UInt16 = 8097
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
    /// `-memoryGuardAt <MB>`: the subtitle memory guard trips with this much
    /// left (a very high one trips at once: checking the swap on a device).
    var memoryGuardMB: Int?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        mock = arguments.contains("-mock")
        Silence.on = (mock && !arguments.contains("-sound")) || arguments.contains("-silent")   // -silent: a real server, no sound (diagnosis runs)
        // `-quickTimers` (UI tests): the app's deliberate waits at a fifth.
        // Set every launch, so an in-process test's can't carry into the next.
        Pace.scale = arguments.contains("-quickTimers") ? 0.2 : 1
        perfHUD = arguments.contains("-perfHUD")
        reset = arguments.contains("-reset")
        benchmark = arguments.contains("-benchmark")
        mockHTTP = arguments.contains("-mockHTTP")
        if let i = arguments.firstIndex(of: "-mockPort"), i + 1 < arguments.count, let port = UInt16(arguments[i + 1]) { mockPort = port }
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
        autoplayBackground = arguments.contains("-autoplayBackground")
        if let i = arguments.firstIndex(of: "-autoplaySubtitles"), i + 1 < arguments.count { autoplaySubtitles = arguments[i + 1] }
        libraryMatrix = arguments.contains("-libraryMatrix")
        if let i = arguments.firstIndex(of: "-memoryGuardAt"), i + 1 < arguments.count { memoryGuardMB = Int(arguments[i + 1]) }
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
    /// The video playing now, for the phone to steer (tracks, seeking).
    @ObservationIgnored weak var player: PlayerController?
    @ObservationIgnored lazy var companion = CompanionBridge(app: self)
    @ObservationIgnored private var defaults: UserDefaults = .standard
    let capabilities: DeviceCapabilities
    private(set) var session: UserSession? { didSet { sessionChanged() } }
    /// Films and episodes on this device (iPhone, iPad, Mac; tvOS keeps no
    /// files an app can count on).
    let downloads: DownloadStore?
    /// What Download does without asking (Settings → Storage).
    var defaultDownloadPreset: DownloadPreset { DownloadPreset(rawValue: settings.downloadQuality) ?? .original }
    /// Watch progress the server didn't get yet (offline), per account.
    var outbox: PlaystateOutbox? { session.map { PlaystateOutbox(defaults: defaults, account: $0.account.id) } }
    var playback: PlaybackRequest?
    /// The player floating in Picture in Picture with its screen closed:
    /// held here so it plays on, and taken back when the screen reopens.
    @ObservationIgnored var floatingPlayer: PlayerController?
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
    /// Every library and where it is in the app (Settings → Libraries).
    var libraryPlan: SidebarPlan?
    /// How many things each library holds (films, shows, audiobooks…), by id.
    var libraryCounts: [String: Int] = [:]

    @ObservationIgnored private var prewarmed: [String: (Task<PlaybackPlan, any Error>, ContinuousClock.Instant)] = [:]
    private static let log = Perf.logger("app")

    /// What an in-process view test (Tests/AppFeaturesTests) swaps in, so
    /// a model keeps nothing of the app's or another test's: settings of its
    /// own, a Keychain in memory, a downloads folder of its own, and a
    /// backend that plays nothing. Links never reach the system: they go to
    /// `openLink` (a test must never open a browser on the Mac it runs on).
    struct StandIns {
        var defaults: UserDefaults
        var keychain = Keychain.inMemory()
        var downloads: URL
        var engine: ((EngineKind) -> any PlayerEngine)?
        var openLink: (URL) -> Void = { _ in }
    }

    @ObservationIgnored let standIns: StandIns?

    init(options: LaunchOptions = LaunchOptions(), standIns: StandIns? = nil) {
        self.options = options
        self.standIns = standIns
        let built = (Bundle.main.executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date })
            .map { $0.formatted(.iso8601) } ?? "?"
        MainThreadWatch.start()
        TraceFile.write("app", "launch \(PerfRecorder.deviceModel) build \(built) args: \(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
        let defaults = standIns?.defaults ?? (options.mock ? UserDefaults(suiteName: "mock")! : .standard)
        downloads = Self.makeDownloads(mock: options.mock, reset: options.reset, directory: standIns?.downloads)
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
        // Your preferences from your other devices (iCloud), before they're read.
        let sync = options.mock ? nil : SettingsSync(defaults: defaults)
        sync?.pull()
        if sync != nil {
            let found = SettingsSync.keys.filter { NSUbiquitousKeyValueStore.default.object(forKey: $0) != nil }.count
            TraceFile.write("settings", "iCloud settings: \(found) of \(SettingsSync.keys.count); iCloud account: \(FileManager.default.ubiquityIdentityToken != nil)")
        }
        settings = AppSettings(defaults: defaults)
        settings.sync = sync
        sync?.seed()
        sync?.onChange = { [settings] in
            TraceFile.write("settings", "changed on another device")
            settings.reloadSynced()
        }
        sync?.start()
        downloads?.allowsCellular = settings.downloadsOverCellular
        libraryUsage = LibraryUsage(defaults: defaults)
        accounts = AccountStore(defaults: defaults, keychain: standIns?.keychain ?? Keychain(service: Brand.bundleIdentifier + (options.mock ? ".mock" : "")), protocolClasses: protocols)
        themes = ThemeStore(settings: settings)
        capabilities = Perf.measureSync("capabilities.probe", "launch.capabilities") { DeviceCapabilities.probe() }

        if !options.mock { accounts.cloud = CloudSignIns() }               // your sign-in on your other devices
        session = accounts.restoreActiveSession()
        if options.mockHTTP, let url = Self.startMockServer(port: options.mockPort) {
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
        if !options.mock, session != nil { Task { await self.checkCloudSignIn() } }
        if Platform.isMac && !options.mock { LocalNetworkAccess.ask() }        // the Mac only asks when the app goes looking
        Self.configureAudioSession()
        InputTrace.install()
        if let session { queue.attach(account: session.id, sleepTimer: sleepTimer, defaults: defaults); startQueueSync(session) }
        sessionChanged()                                          // (didSet doesn't run in init)
        self.defaults = defaults
        FocusTracker.onFeatured = { [weak self] item in self?.focusedItem = item }
        // Only the TV answers phones: a phone or Mac advertising itself showed
        // up in the phone's list of TVs.
        applyRemoteSetting()
        #if DEBUG
        Task { @MainActor in try? await Task.sleep(for: .seconds(2)); await self.probeSubtitles(); await self.probeDownloads() }
        #endif
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
        if options.libraryMatrix, let client = session?.client { Task { await LibraryMatrix.pick(client: client) } }
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
                        if options.autoplayBackground {
                            // A subtitle of the asked kind on (the matrix measures drawing them).
                            let subtitle = options.autoplaySubtitles.flatMap { want in
                                item.mediaSources?.first?.subtitleStreams.first { s in
                                    let c = (s.codec ?? "").lowercased()
                                    let kind = ["pgssub", "dvdsub", "dvd_subtitle", "hdmv_pgs_subtitle", "dvbsub"].contains(c) ? "bitmap" : ["ass", "ssa"].contains(c) ? "ass" : "text"
                                    return kind == want
                                }?.index
                            }
                            self.playback = PlaybackRequest(item: item, resume: true, subtitleIndex: subtitle ?? -1, background: true)
                            return
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
    private static func startMockServer(port: UInt16) -> URL? {
        for attempt in 1...20 {
            do { return try MockHTTPServer.shared.start(port: port) } catch {
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
        AudioSessionReport.start()
        #endif
    }

    var planner: PlaybackPlanner {
        let budget = SoftwareDecodeBudget.forModel(options.simulateModel ?? PerfRecorder.hardwareModel)
        var planner = PlaybackPlanner(
            capabilities: capabilities, preference: settings.enginePreference, maxBitrate: settings.maxBitrate,
            softwareDecodeCheck: { codec, w, h, fps in budget.allows(codec: codec, pixelRate: Double(w * h) * fps) }
        )
        planner.allowsTranscoding = !settings.disableTranscoding
        return planner
    }

    // MARK: Session

    private static func makeDownloads(mock: Bool, reset: Bool, directory: URL? = nil) -> DownloadStore? {
        guard !Platform.isTV else { return nil }
        guard mock else { return DownloadStore() }
        // Tests: their own folder, and the mock server (a background session can't use one).
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Downloads-mock", directoryHint: .isDirectory)
        if reset { try? FileManager.default.removeItem(at: dir) }
        let config = URLSessionConfiguration.default
        config.protocolClasses = [MockJellyfinProtocol.self]
        return DownloadStore(directory: dir, configuration: config)
    }

    private func sessionChanged() {
        guard let session else { return }
        downloads?.use(session.client, for: session.account.id)
    }

    /// Signing in from iCloud: who, while it happens (the first screen says so).
    private(set) var cloudSignIn: String?

    /// No sign-in on this device, but one on another (iCloud Keychain): sign
    /// in as that person with a sign-in of this device's own — its Quick
    /// Connect code approved with the shared one — or, with Quick Connect
    /// off on the server, the shared sign-in itself.
    func signInFromCloud() async {
        guard session == nil, cloudSignIn == nil, let cloud = accounts.cloud else { return }
        let list = await cloud.load()
        TraceFile.write("accounts", "iCloud sign-ins: \(list.map { String($0.count) } ?? "unknown")\(await cloud.lastError.map { " (\($0))" } ?? "")")
        guard session == nil, cloudSignIn == nil, let entry = list?.first else { return }
        cloudSignIn = "\(entry.account.userName) on \(entry.server.name)"
        defer { cloudSignIn = nil }
        TraceFile.write("accounts", "signing in from iCloud as \(entry.account.userName) on \(entry.server.name)")
        let mine = accounts.client(for: entry.server, userId: entry.account.userId)
        let theirs = accounts.client(for: entry.server, userId: entry.account.userId).authenticated(token: entry.token, userId: entry.account.userId)
        do {
            guard try await mine.quickConnectEnabled() else { throw JellyfinError.unauthorized }
            let state = try await mine.quickConnectInitiate()
            try await theirs.quickConnectAuthorize(code: state.code)
            for _ in 0..<10 {
                if (try? await mine.quickConnectState(secret: state.secret))?.authenticated == true { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            let result = try await mine.authenticate(quickConnectSecret: state.secret)
            TraceFile.write("accounts", "signed in from iCloud with this device's own sign-in")
            didSignIn(accounts.signIn(server: entry.server, result: result))
        } catch {
            // Quick Connect off (or refused): the shared sign-in, if it still works.
            guard (try? await theirs.currentUser()) != nil else {
                TraceFile.write("accounts", "iCloud sign-in no longer works: \(error)")
                return
            }
            TraceFile.write("accounts", "signed in from iCloud with the shared sign-in (\(error))")
            didSignIn(accounts.adopt(entry))
        }
    }

    /// Signed in here: signed out on another device since (so here too), or
    /// not in iCloud yet (put it there for the others).
    func checkCloudSignIn() async {
        guard let cloud = accounts.cloud, session != nil else { return }
        guard let list = await cloud.load() else {                     // iCloud couldn't say: change nothing
            TraceFile.write("accounts", "iCloud sign-ins unknown: \(await cloud.lastError ?? "?")")
            return
        }
        TraceFile.write("accounts", "iCloud sign-ins: \(list.count)")
        if accounts.signedOutElsewhere(list) { signOutHere(reason: "signed out on another device"); return }
        await accounts.shareActive(list)
        if let error = await cloud.lastError { TraceFile.write("accounts", "sharing the sign-in failed: \(error)") }
    }

    /// Signed out on another device: here too.
    private func signOutHere(reason: String) {
        guard let session else { return }
        TraceFile.write("accounts", reason)
        let client = session.client
        Task { try? await client.logout() }
        accounts.signOut(session.account.id)
        self.session = nil
    }

    func didSignIn(_ session: UserSession) {
        self.session = session
        queue.attach(account: session.id, sleepTimer: sleepTimer, defaults: defaults)
        startQueueSync(session)
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
        if route == "downloads" { return [.downloads] }
        let parts = route.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        switch parts[0] {
        case "item": return [.item(BaseItem(id: parts[1], name: nil, kind: .movie))]
        case "person": return [.person(Person(id: parts[1], name: nil))]
        case "library":
            var lib = BaseItem(id: parts[1], name: "Movies", kind: .collectionFolder)
            lib.collectionType = "movies"
            return [.library(lib)]
        case "shows":
            var lib = BaseItem(id: parts[1], name: "TV Shows", kind: .collectionFolder)
            lib.collectionType = "tvshows"
            return [.library(lib)]
        case "books":
            var lib = BaseItem(id: parts[1], name: "Audiobooks", kind: .collectionFolder)
            lib.collectionType = "books"
            return [.library(lib)]
        case "audiobook": return [.audiobook(parts[1])]
        case "queue": return [.queue]
        case "settings": return [.settings(parts[1])]
        case "profile": return [.profile]
        case "new":                                       // new:episodes:<library id>
            let rest = parts[1].split(separator: ":", maxSplits: 1).map(String.init)
            guard rest.count == 2, let kind = ArrivalKind(rawValue: rest[0]) else { return [] }
            return [.arrivals(ArrivalsSpec(kind: kind, libraryId: rest[1], title: kind.title))]
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

    /// The queue on every device of the account (Jellyfin keeps it). Not in
    /// mock runs: tests shouldn't depend on each other's plans.
    @ObservationIgnored private var queueSync: QueueSync?

    private func startQueueSync(_ session: UserSession) {
        queueSync?.stop()
        guard !options.mock || ProcessInfo.processInfo.arguments.contains("-syncQueue") else { queueSync = nil; return }
        let sync = QueueSync(store: queue, client: session.client)
        sync.start()
        queueSync = sync
    }

    /// Back to the front: catch up with changes made on other devices.
    #if DEBUG
    /// `-downloadProbe [itemId]` (debug builds, a real server): downloads an
    /// item (default: the shortest episode) as the original, checks the file
    /// is video and opens, removes it; then the same as a Small transcode.
    /// Traces each step; leaves nothing behind.
    func probeDownloads() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-downloadProbe"), let session, let store = downloads else { return }
        let client = session.client
        let given = i + 1 < args.count && !args[i + 1].hasPrefix("-") ? args[i + 1] : nil
        var id = given
        if id == nil {
            // A real episode (sorting by length found a missing one, 0 KB): Next Up's shortest.
            let next = (try? await client.nextUp(limit: 20).items) ?? []
            id = next.filter { ($0.runTimeTicks ?? 0) > 0 }.min { ($0.runTimeTicks ?? 0) < ($1.runTimeTicks ?? 0) }?.id
        }
        guard let id, let item = try? await client.item(id: id) else { TraceFile.write("downloads", "probe: no item"); return }
        TraceFile.write("downloads", "probe: \(item.seriesName ?? "") \(item.name ?? id), \(item.runtime.map { Int($0.seconds) } ?? 0) s, source \(item.mediaSources?.first?.container ?? "?") \(item.mediaSources?.first?.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?")")
        let only = args.firstIndex(of: "-downloadProbeOnly").flatMap { args.indices.contains($0 + 1) ? DownloadPreset(rawValue: args[$0 + 1]) : nil }
        for preset in only.map({ [$0] }) ?? [DownloadPreset.original, .small] {
            store.remove([id])
            try? await Task.sleep(for: .milliseconds(300))
            let start = ContinuousClock.now
            store.download([item], client: client, accountId: session.account.id, quality: preset.quality)
            var record: DownloadRecord?
            for tick in 0..<1200 {                                // up to 10 minutes
                try? await Task.sleep(for: .milliseconds(500))
                record = store.record(id)
                if tick % 30 == 29, let r = record {
                    let done = r.pieces.filter { $0.file != nil }.count
                    TraceFile.write("downloads", "probe \(preset.rawValue): \(ByteCountFormatter.string(fromByteCount: r.received, countStyle: .file)) so far, \(done)/\(r.pieces.count) pieces, \(String(describing: r.state))")
                }
                if let r = record, r.isDone { break }
                if case .failed? = record?.state { break }
            }
            let secs = (ContinuousClock.now - start).components.seconds
            guard let r = record, r.isDone, let file = store.localFile(for: id) else {
                TraceFile.write("downloads", "probe \(preset.rawValue): FAILED after \(secs) s — \(String(describing: record?.state))")
                continue
            }
            let head = (try? FileHandle(forReadingFrom: file).read(upToCount: 12)) ?? Data()
            let kind = head.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) ? "Matroska" : head.dropFirst(4).starts(with: Array("ftyp".utf8)) ? "MP4" : "unknown (\(head.map { String(format: "%02x", $0) }.joined()))"
            let asset = AVURLAsset(url: file)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            let duration = (try? await asset.load(.duration)).map { Int($0.seconds) } ?? -1
            let size = r.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?"
            let rate = r.size.map { Double($0) / max(1, Double(secs)) / 1_048_576 } ?? 0
            let plan = planner.localPlan(item: r.item, source: r.item.mediaSources?.first ?? item.mediaSources![0], file: file, startPosition: nil, audioIndex: nil, subtitleIndex: nil)
            TraceFile.write("downloads", "probe \(preset.rawValue): \(size) in \(secs) s (\(String(format: "%.1f", rate)) MB/s), \(r.pieces.count) piece(s), \(kind), AVFoundation playable \(playable), \(duration) s, plays in \(plan.engine.rawValue), subtitles \(r.subtitles?.count ?? 0)")
        }
        store.remove([id])
        TraceFile.write("downloads", "probe: done, removed")
    }

    /// `-subtitleProbe [itemId]` (debug builds): runs Find Subtitles' search
    /// and ranking for an item (default: the first one in progress) on the
    /// signed-in server and traces what comes back. Searches only; nothing
    /// is downloaded.
    func probeSubtitles() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-subtitleProbe"), let client = session?.client else { return }
        let given = i + 1 < args.count && !args[i + 1].hasPrefix("-") ? args[i + 1] : nil
        var fallback: String?
        if given == nil { fallback = try? await client.resumeItems(limit: 1).items.first?.id }
        guard let id = given ?? fallback, let item = try? await client.item(id: id),
              let source = item.mediaSources?.first else {
            TraceFile.write("subtitles", "probe: no item to try"); return
        }
        let video = (source.mediaStreams ?? []).first { $0.type == .video }
        let file = SubtitleFile(title: item.seriesName ?? item.name ?? "", year: item.productionYear,
                                season: item.kind == .episode ? item.parentIndexNumber : nil, episode: item.kind == .episode ? item.indexNumber : nil,
                                fileName: source.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? source.name,
                                fps: video?.realFrameRate ?? video?.averageFrameRate,
                                durationSeconds: item.runTimeTicks.map { Double($0) / Double(BaseItem.ticksPerSecond) })
        let language = PlayerController.preferredLanguage()
        TraceFile.write("subtitles", "probe: \(file.title) S\(file.season ?? 0)E\(file.episode ?? 0) [\(file.fileName ?? "?")] in \(language)")
        do {
            let found = try await client.remoteSubtitles(itemId: item.id, language: language)
            let (ranked, judgedBy) = await subtitleRanker.rank(found, for: file)
            TraceFile.write("subtitles", "probe: \(found.count) found, judged on \(judgedBy)")
            for f in ranked.prefix(5) { TraceFile.write("subtitles", "probe:   \(f.confidenceText)  \(f.name)  — \(f.reasons.joined(separator: "; "))") }
        } catch {
            TraceFile.write("subtitles", "probe: search failed: \(error)")
        }
    }
    #endif

    func refreshFromOtherDevices() {
        if !options.mock {
            if session == nil { Task { await signInFromCloud() } } else { Task { await checkCloudSignIn() } }
        }
        Task { await queueSync?.pull() }
        if let outbox, let client = session?.client { Task { await outbox.deliver(with: client) } }
        Task { await refreshProfile() }
    }

    /// The account's name and picture as the server has them now (it was
    /// only read at sign-in, so a new picture never showed).
    private func refreshProfile() async {
        guard let session, !options.mock, let user = try? await session.client.currentUser() else { return }
        guard accounts.updateProfile(session.account.id, name: user.name, imageTag: user.primaryImageTag),
              self.session?.id == session.id else { return }
        self.session = accounts.restoreActiveSession()
    }

    // MARK: Playback

    /// In or out of the Queue (the TV's too, while connected to one).
    func toggleQueue(_ item: BaseItem) {
        let adding = !queue.contains(item.id)
        queue.toggle(item)
        casting?.queue(item.id, adding)
    }

    /// Background: a show from a random episode (or this episode, or this
    /// film), on a loop, without marking anything watched.
    func playInBackground(_ item: BaseItem) {
        if let cast = casting {
            cast.play(item.id, false, true)
            return
        }
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

    /// The iPhone/iPad's link to an Apple TV: while connected, Play,
    /// Background and Queue go to the TV.
    @ObservationIgnored var cast: CastLink?

    /// Settings → Remote: the TV answers phones (only the TV: a phone or Mac
    /// advertising itself showed up in the phone's list of TVs); a phone
    /// looks for TVs.
    func applyRemoteSetting() {
        let on = settings.allowRemote
        if Platform.isTV { on ? companion.start() : companion.stop() }
        cast?.enabled = on
    }

    /// Connected to a TV: what's played goes there (books stay on the phone).
    private var casting: CastLink? { cast?.isConnected == true ? cast : nil }

    /// `sequence`: what plays after it, in turn (a playlist's rest).
    func play(_ item: BaseItem, resume: Bool = true, mediaSourceId: String? = nil, audioIndex: Int? = nil, subtitleIndex: Int? = nil,
              sequence: [BaseItem] = []) {
        if let cast = casting {
            TraceFile.write("cast", "play \(item.name ?? item.id) on \(cast.connectedTo ?? "?")")
            libraryUsage.recordPlay(item, libraries: libraries)
            cast.play(item.id, resume, false)
            return
        }
        if audiobook != nil { stopAudiobook() }             // one thing plays at a time
        libraryUsage.recordPlay(item, libraries: libraries)
        playback = PlaybackRequest(item: item, resume: resume, mediaSourceId: mediaSourceId, audioIndex: audioIndex, subtitleIndex: subtitleIndex,
                                   sequence: sequence)
    }

    /// Fires PlaybackInfo as soon as a Play button *gets focus*, so by the time
    /// the user clicks, the server round trip is already done. Plans are reused
    /// for 60 s.
    func prewarm(_ item: BaseItem) {
        // A downloaded item plays from its file: nothing to ask the server.
        guard let session, item.kind.isPlayable, downloads?.localFile(for: item.id) == nil else { return }
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
        if let standIn = standIns?.engine { return standIn(kind) }
        return switch kind {
        case .native: NativeEngine()
        case .vlc: VLCEngine(subtitleStyle: VLCSubtitleStyle(settings.subtitleStyle, scale: settings.subtitleScale, font: settings.subtitleFont))
        }
    }

    /// The detail page's Play button has focus — the strongest "about to
    /// press Play" signal there is. Plans that one item and, if it's a VLCKit
    /// item, opens and buffers it.
    func prepare(_ item: BaseItem) {
        guard !options.noPrepare, item.kind.isPlayable, playback == nil, floatingPlayer == nil, downloads?.localFile(for: item.id) == nil,
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
