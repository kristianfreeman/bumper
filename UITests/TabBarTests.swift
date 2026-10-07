import XCTest

/// The tab bar along the top (like the Music app's): reached from the page
/// with Up and Menu, and left with Down back to the page's cards.
@MainActor
final class TabBarTests: XCTestCase {
    /// Up from the first card, and Menu, both put focus on the tabs; Down
    /// goes back to the cards (not to the profile corner on the way).
    func testUpAndMenuReachTheTabsAndDownComesBack() {
        let app = launchHome()
        let remote = XCUIRemote.shared
        remote.press(.up)
        onTabs(app)
        let afterUp = focusedDescription(app)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/tabbar.png"))
        }
        XCTAssertTrue(afterUp.hasPrefix("TABBAR"), "Up from the first card: focus on \(afterUp), not the tabs")
        remote.press(.down)
        waitUntil(2) { app.focused.identifier.hasPrefix("card.") }
        XCTAssertTrue(app.focused.identifier.hasPrefix("card."), "Down from the tabs: focus on \(focusedDescription(app)), not a card")
        remote.press(.menu)
        XCTAssertTrue(onTabs(app), "Menu: focus on \(focusedDescription(app)), not the tabs")
    }

    /// Scrolled down the page, Menu goes back up to the tabs (in one press
    /// or two, as in Apple's apps).
    func testMenuFromALowerRowReachesTheTabs() {
        let app = launchHome()
        let remote = XCUIRemote.shared
        for _ in 0..<3 { remote.press(.down, movingFocusIn: app) }
        let onCard = focusedDescription(app)
        remote.press(.menu)
        if !onTabs(app) { remote.press(.menu) }
        XCTAssertTrue(onTabs(app), "Menu from \(onCard): focus on \(focusedDescription(app))")
    }

    /// After watching something and leaving the player, the tabs still answer.
    func testTabsAfterLeavingThePlayer() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockPort", "0", "-mockMedia", PlayerTests.media, "-reset", "-autoplay", "media-1"]
        app.launch()
        let time = app.staticTexts["player.time"]
        XCTAssertTrue(time.exists(within: 8), "player didn't open")
        let remote = XCUIRemote.shared
        for _ in 0..<3 where time.exists {                          // hide controls, then leave
            remote.press(.menu)
            time.gone(within: 1)
        }
        XCTAssertFalse(time.exists, "couldn't leave the player")
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].exists(within: 5))
        app.focusSettles()
        remote.press(.up)
        XCTAssertTrue(onTabs(app), "After the player, Up: focus on \(focusedDescription(app))")
    }
}

/// Along the tab bar: each tab's page, the profile at the end, and room
/// for every library.
@MainActor
final class TabBarPlacesTests: XCTestCase {
    /// Moving along the tabs changes the page; Down lands in that page.
    func testMovingAlongTheTabsChangesThePage() {
        let app = launchHome()
        let remote = XCUIRemote.shared
        remote.press(.up)
        onTabs(app)
        remote.press(.right, movingFocusIn: app)                // Home → the first library
        let tab = focusedDescription(app)
        XCTAssertTrue(tab.hasPrefix("TABBAR"), "Right along the tabs: focus on \(tab)")
        let resume = app.descendants(matching: .any)["collection.resume"]
        let onHome = { resume.exists && resume.isHittable }     // (isHittable on what's gone looks again for a second)
        waitUntil(3) { !onHome() }                              // its page in
        app.focusSettles(quiet: 0.2)
        remote.press(.down)
        waitUntil(3) { !onHome() && !focusedDescription(app).hasPrefix("TABBAR") }
        XCTAssertFalse(onHome(), "still on Home after moving to \(tab)")
        XCTAssertFalse(focusedDescription(app).hasPrefix("TABBAR"), "Down from \(tab) didn't reach the page")
    }

    /// You're the last tab (your picture and name): Right along the tabs
    /// reaches it, it opens your profile, and Down goes into that page.
    func testTheProfileIsTheLastTab() {
        let app = launchHome()
        let remote = XCUIRemote.shared
        remote.press(.up)
        onTabs(app)
        let profile = app.buttons["Tester"]
        XCTAssertTrue(remote.press(.right, in: app, atMost: 8) { profile.hasFocus }, "couldn't reach the profile tab (focus: \(focusedDescription(app)))")
        XCTAssertTrue(app.staticTexts["Episodes watched"].exists(within: 3), "the profile tab didn't show the profile")
        remote.press(.left, movingFocusIn: app)
        XCTAssertTrue(focusedDescription(app).hasPrefix("TABBAR"), "Left from the profile tab: focus on \(focusedDescription(app))")
    }

    /// A real server's spread of libraries (two books libraries, collections,
    /// playlists, home videos) and two more: every tab is on the bar.
    func testEveryLibraryTabFits() {
        let app = launchHome(["-mockLibraries", "Books:books,Collections:boxsets,Playlists:playlists,Videos:homevideos,Kids:movies,Anime:tvshows"])
        XCUIRemote.shared.press(.up)
        onTabs(app)
        app.focusSettles()                                          // the bar done growing in
        let window = app.windows.firstMatch.frame
        let tabs = app.descendants(matching: .any).matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.button.rawValue)).allElementsBoundByIndex
            .filter { $0.frame.maxY < 170 && $0.frame.width > 0 }
        print("TABBAR-DEBUG tabs: \(tabs.map { "'\($0.label)'" }.joined(separator: " "))")
        XCTAssertGreaterThanOrEqual(tabs.count, 5, "too few tabs on the bar")
        for t in tabs { XCTAssertTrue(window.contains(t.frame), "tab '\(t.label)' runs off the screen") }
    }
}

@MainActor
extension XCTestCase {
    /// What has focus, in one look (each property of an element is another).
    fileprivate func focusedDescription(_ app: XCUIApplication) -> String {
        guard let f = try? app.focused.snapshot() else { return "nothing" }
        // Tab bar items: along the top of the screen, and not the profile corner.
        let inTabBar = f.frame.maxY < 170
        return "\(inTabBar ? "TABBAR " : "")\(f.elementType.rawValue) '\(f.label)' [\(f.identifier)] \(Int(f.frame.minX)),\(Int(f.frame.minY)) \(Int(f.frame.width))x\(Int(f.frame.height))"
    }

    /// Until focus is on the tabs, and done moving there (a press while
    /// the bar is still taking it went nowhere).
    @discardableResult
    fileprivate func onTabs(_ app: XCUIApplication, within timeout: TimeInterval = 2) -> Bool {
        guard waitUntil(timeout, { focusedDescription(app).hasPrefix("TABBAR") }) else { return false }
        app.focusSettles(quiet: 0.2)
        return focusedDescription(app).hasPrefix("TABBAR")
    }

    fileprivate func launchHome(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].exists(within: 8))
        app.focusSettles()
        return app
    }
}
