#if os(macOS)                    // in-process view tests: the Mac's `swift test`
@testable import AppFeatures
import AppCore
import AppKit
import ApplicationServices
import DesignSystem
import Foundation
import JellyfinMocks
import PlaybackCore
import SwiftUI
import Synchronization
import Testing

/// In-process view tests: the real `AppModel` on the in-process mock server
/// (what `-mock` launches), real SwiftUI pages in a window that's never
/// shown, read and pressed through their accessibility — the identifiers
/// and words the XCUITests use — but in the test's own process, so a check
/// takes milliseconds, not a simulator's seconds.
///
///     let screen = Screen(route: "item:movie-0001")     // as `-route` opens it
///     try await screen.wait(for: "detail.play")
///     try await screen.press("person.person-a01")
///     #expect(screen.text("Cast & Crew") != nil)
///
/// Waits poll every few milliseconds up to a deadline: never a fixed sleep.
/// The player runs on `FakeEngine` (no media decoded); `screen.engine` is
/// the one it made.
///
/// What it can't check: these are the Mac's forms of the pages (its layout,
/// its pointer controls — not the TV's `#if os(tvOS)` code or the phone's);
/// and nothing of the TV's focus engine, the Siri Remote, keyboards, menus
/// that pop up, or the system's own windows. Those stay in UITests/.
@MainActor
final class Screen {
    let app: AppModel
    /// The player's backends, newest last (a hand-over makes a second).
    private(set) var engines: [FakeEngine] = []
    var engine: FakeEngine? { engines.last }
    /// What the next backend does (e.g. hold its start: a slow one).
    var nextEngine: (FakeEngine) -> Void = { _ in }

    private let window: NSWindow
    private let saved: Saved

    /// A page's window: tall, so lazy rows have room to be built.
    static let page = CGSize(width: 1280, height: 1400)
    /// The player's spaces: wider than tall (the picture full screen), and
    /// taller than wide (a portrait window: the picture over the controls).
    static let wide = CGSize(width: 1280, height: 720)
    static let tall = CGSize(width: 720, height: 1280)

    /// The app as `-mock <arguments>` launches it, showing `content`.
    convenience init<Content: View>(_ arguments: [String] = [], size: CGSize = Screen.page, @ViewBuilder content: (AppModel) -> Content) {
        self.init(arguments, size: size, saved: Saved(), content: content)
    }

    private init<Content: View>(_ arguments: [String], size: CGSize, saved: Saved, @ViewBuilder content: (AppModel) -> Content) {
        Self.setUpOnce()
        self.saved = saved
        var standIns = AppModel.StandIns(defaults: UserDefaults(suiteName: saved.suite)!, downloads: saved.folder.appending(path: "Downloads"))
        var make: (EngineKind) -> any PlayerEngine = { FakeEngine(kind: $0) }
        standIns.engine = { make($0) }
        app = AppModel(options: LaunchOptions(arguments: ["Bumper", "-mock", "-mockMedia", Self.media.path] + arguments), standIns: standIns)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content(app).appEnvironment(app).frame(width: size.width, height: size.height))
        make = { [weak self] kind in
            let engine = FakeEngine(kind: kind)
            self?.nextEngine(engine)
            self?.engines.append(engine)
            return engine
        }
    }

    /// A page as a deep link (`-route item:<id>`, `person:<id>`, …) opens it.
    convenience init(route: String, size: CGSize = Screen.page) {
        self.init(["-route", route], size: size) { app in RoutedStack(initial: app.launchRoute) { Color.clear } }
    }

    /// The player, as the app presents it whenever something plays
    /// (`-autoplay <id>` starts it; so does any Play on a page).
    static func player(_ arguments: [String], size: CGSize = Screen.wide) -> Screen {
        Screen(arguments, size: size) { app in PlayerStage(app: app) }
    }

    /// The app launched again on what this one saved (settings, the queue,
    /// downloads): a UI test's relaunch without `-reset`.
    func relaunch<Content: View>(_ arguments: [String] = [], size: CGSize = Screen.page, @ViewBuilder content: (AppModel) -> Content) -> Screen {
        Screen(arguments, size: size, saved: saved, content: content)
    }

    isolated deinit {
        window.close()                                   // the player goes, as when it's closed
    }

    /// What a run keeps between launches; cleared once no screen uses it.
    private final class Saved {
        static let prefix = "view-test-"
        let suite = Saved.prefix + UUID().uuidString
        let folder: URL

        init() { folder = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory) }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        /// The preferences system leaves an empty file for each settings
        /// suite, even removed: earlier runs' go as a run starts.
        static func sweep() {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Preferences", directoryHint: .isDirectory)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: dir.appending(path: name))
            }
        }
    }

    // MARK: Reading

    /// Everything on screen, in reading order.
    var elements: [Element] {
        var out: [Element] = []
        func walk(_ any: Any) {
            guard let node = any as? NSObject else { return }
            let element = Element(node)
            out.append(element)
            for child in element.children { walk(child) }
        }
        walk(window.contentView as Any)
        return out
    }

    func element(_ id: String) -> Element? { elements.first { $0.id == id } }
    func elements(prefix: String) -> [Element] { elements.filter { $0.id.hasPrefix(prefix) } }
    /// The first element that says exactly this.
    func text(_ words: String) -> Element? { elements.first { $0.text == words } }

    // MARK: Waiting

    /// Until `condition` holds, polling every few milliseconds; past the
    /// deadline, fails saying what was on screen.
    func waitUntil(_ what: String, timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NotOnScreen(waitingFor: what, onScreen: elements) }
            try await Task.sleep(for: .milliseconds(4))
        }
    }

    @discardableResult
    func wait(for id: String, timeout: Duration = .seconds(3), where matches: (Element) -> Bool = { _ in true }) async throws -> Element {
        var found: Element?
        try await waitUntil(id, timeout: timeout) {
            found = element(id).flatMap { matches($0) ? $0 : nil }
            return found != nil
        }
        return found!
    }

    @discardableResult
    func wait(forText words: String, timeout: Duration = .seconds(3)) async throws -> Element {
        var found: Element?
        try await waitUntil("“\(words)”", timeout: timeout) {
            found = text(words)
            return found != nil
        }
        return found!
    }

    /// Every element whose identifier starts so, once there's one.
    @discardableResult
    func wait(forAny prefix: String, timeout: Duration = .seconds(3)) async throws -> [Element] {
        var found: [Element] = []
        try await waitUntil("\(prefix)…", timeout: timeout) {
            found = elements(prefix: prefix)
            return !found.isEmpty
        }
        return found
    }

    func waitUntilGone(_ id: String, timeout: Duration = .seconds(3)) async throws {
        try await waitUntil("\(id) to go", timeout: timeout) { element(id) == nil }
    }

    /// Until nothing on screen has changed for `quiet`: before checking
    /// that something *isn't* there (it could still be on its way).
    func settle(quiet: Duration = .milliseconds(60), timeout: Duration = .seconds(3)) async throws {
        var last = elements.map(\.description)
        var since = ContinuousClock.now
        try await waitUntil("the screen to settle", timeout: timeout) {
            let now = elements.map(\.description)
            if now != last { last = now; since = .now }
            return ContinuousClock.now - since >= quiet
        }
    }

    // MARK: Acting

    /// Presses it (a click, a tap), once it's there.
    func press(_ id: String) async throws {
        let element = try await wait(for: id)
        guard element.press() else { throw NotOnScreen(waitingFor: "\(id) to take a press", onScreen: elements) }
    }

    // MARK: Once per run

    /// Clips the mock serves as `media-0…` (only their description: the
    /// fake backend never reads a file). Two minutes, with the mock's
    /// chapters at 0:30, 1:00 and 1:30.
    static let media: URL = {
        let dir = FileManager.default.temporaryDirectory.appending(path: "view-test-media", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let clip = #"[{"file":"clip.mp4","name":"Seek Clip","container":"mp4","duration":120,"video":{"codec":"h264","width":1920,"height":1080,"fps":24,"range":"SDR","bitDepth":8},"audio":[{"codec":"aac","channels":2,"title":"Stereo"}],"subtitles":[]}]"#
        try? Data(clip.utf8).write(to: dir.appending(path: "manifest.json"))
        return dir
    }()

    private static var isSetUp = false

    private static func setUpOnce() {
        guard !isSetUp else { return }
        isSetUp = true
        Saved.sweep()
        MockJellyfinProtocol.latency.withLock { $0 = .zero }       // the mock answers at once
        // SwiftUI builds its accessibility tree only once something asks for
        // it as an assistive app would. One question to this process through
        // the public AX API (it needs a launched NSApplication to answer)
        // turns it on for the rest of the run.
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.finishLaunching()
        var role: CFTypeRef?
        let asked = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()), kAXRoleAttribute as CFString, &role)
        precondition(asked == .success, "Accessibility didn't answer (\(asked.rawValue)): view tests can't read the screen")
    }
}

/// Every view test, one at a time (each file adds its suite in an
/// extension): they all run on the main thread, and side by side their
/// polling starved SwiftUI of the turns it draws in — pages came up blank.
@Suite("On screen", .serialized)
struct OnScreen {}

/// One thing on screen, as accessibility sees it.
@MainActor
struct Element: CustomStringConvertible {
    let id: String
    let role: String
    let label: String
    let value: String
    let isSelected: Bool
    private let node: NSObject

    /// Read by name: SwiftUI's elements answer the NSAccessibility methods
    /// without declaring the protocol (so a cast to it fails).
    init(_ node: NSObject) {
        self.node = node
        func read(_ getter: String) -> Any? { node.responds(to: NSSelectorFromString(getter)) ? node.value(forKey: getter) : nil }
        id = read("accessibilityIdentifier") as? String ?? ""
        role = read("accessibilityRole") as? String ?? ""
        label = read("accessibilityLabel") as? String ?? ""
        value = read("accessibilityValue").map { "\($0)" } ?? ""
        isSelected = read("isAccessibilitySelected") as? Bool ?? false
    }

    var children: [Any] {
        node.responds(to: NSSelectorFromString("accessibilityChildren")) ? node.value(forKey: "accessibilityChildren") as? [Any] ?? [] : []
    }

    /// What it says: its label, else its value (a Text's words are its value).
    var text: String { label.isEmpty ? value : label }

    /// A click on AppKit's own controls (a switch); an accessibility press on
    /// SwiftUI's. Not a menu: its pop-up would wait for a person.
    @discardableResult func press() -> Bool {
        if node is NSPopUpButton { return false }
        if let control = node as? NSControl {
            control.performClick(nil)
            return true
        }
        return (node as AnyObject).accessibilityPerformPress?() ?? false
    }

    var description: String { [id.isEmpty ? nil : id, text.isEmpty ? nil : "“\(text)”"].compactMap { $0 }.joined(separator: " ") }
}

/// A wait that ran out, with what was there instead.
nonisolated struct NotOnScreen: Error, CustomStringConvertible {
    let waitingFor: String
    let onScreen: [String]

    @MainActor init(waitingFor: String, onScreen: [Element]) {
        self.waitingFor = waitingFor
        self.onScreen = onScreen.map(\.description).filter { !$0.isEmpty }
    }

    var description: String { "Gave up waiting for \(waitingFor). On screen: \(onScreen.prefix(80).joined(separator: ", "))" }
}

/// The player over everything, as `RootView` presents it on the Mac.
private struct PlayerStage: View {
    @Bindable var app: AppModel

    var body: some View {
        Color.black.fullScreen(item: $app.playback) { request in
            PlayerView(request: request)
        }
    }
}
#endif
