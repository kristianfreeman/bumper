import XCTest

/// The tab bar along the top (like the Music app's): reached from the page
/// with Up and Menu, and left with Down back to the page's cards.
@MainActor
final class TabBarTests: XCTestCase {
    func focused(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }

    func focusedDescription(_ app: XCUIApplication) -> String {
        let f = focused(app)
        guard f.exists else { return "nothing" }
        // Tab bar items: along the top of the screen, and not the profile corner.
        let inTabBar = f.frame.maxY < 170
        return "\(inTabBar ? "TABBAR " : "")\(f.elementType.rawValue) '\(f.label)' [\(f.identifier)] \(Int(f.frame.minX)),\(Int(f.frame.minY)) \(Int(f.frame.width))x\(Int(f.frame.height))"
    }

    private func launchHome(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    /// Up from the first card, and Menu, both put focus on the tabs; Down
    /// goes back to the cards (not to the profile corner on the way).
    func testUpAndMenuReachTheTabsAndDownComesBack() {
        let app = launchHome()
        let remote = XCUIRemote.shared
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.8)
        let afterUp = focusedDescription(app)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/tabbar.png"))
        }
        XCTAssertTrue(afterUp.hasPrefix("TABBAR"), "Up from the first card: focus on \(afterUp), not the tabs")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(focused(app).identifier.hasPrefix("card."), "Down from the tabs: focus on \(focusedDescription(app)), not a card")
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        let afterMenu = focusedDescription(app)
        XCTAssertTrue(afterMenu.hasPrefix("TABBAR"), "Menu: focus on \(afterMenu), not the tabs")
    }

    /// Scrolled down the page, Menu goes back up to the tabs (in one press
    /// or two, as in Apple's apps).
    func testMenuFromALowerRowReachesTheTabs() {
        let app = launchHome()
        let remote = XCUIRemote.shared
        for _ in 0..<3 { remote.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        let onCard = focusedDescription(app)
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        if !focusedDescription(app).hasPrefix("TABBAR") { remote.press(.menu); Thread.sleep(forTimeInterval: 1) }
        XCTAssertTrue(focusedDescription(app).hasPrefix("TABBAR"), "Menu from \(onCard): focus on \(focusedDescription(app))")
    }

    /// Moving along the tabs changes the page; Down lands in that page.
    func testMovingAlongTheTabsChangesThePage() {
        let app = launchHome()
        let remote = XCUIRemote.shared
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.8)
        remote.press(.right)                                    // Home → the first library
        Thread.sleep(forTimeInterval: 1.5)
        let tab = focusedDescription(app)
        XCTAssertTrue(tab.hasPrefix("TABBAR"), "Right along the tabs: focus on \(tab)")
        remote.press(.down)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.descendants(matching: .any)["collection.resume"].isHittable, "still on Home after moving to \(tab)")
        XCTAssertFalse(focusedDescription(app).hasPrefix("TABBAR"), "Down from \(tab) didn't reach the page")
    }

    /// You're the last tab (your picture and name): Right along the tabs
    /// reaches it, it opens your profile, and Down goes into that page.
    func testTheProfileIsTheLastTab() {
        let app = launchHome()
        let remote = XCUIRemote.shared
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.8)
        let profile = app.buttons["Tester"]
        for _ in 0..<8 where !profile.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(profile.hasFocus, "couldn't reach the profile tab (focus: \(focusedDescription(app)))")
        XCTAssertTrue(app.staticTexts["Episodes watched"].waitForExistence(timeout: 3), "the profile tab didn't show the profile")
        remote.press(.left)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(focusedDescription(app).hasPrefix("TABBAR"), "Left from the profile tab: focus on \(focusedDescription(app))")
    }

    /// After watching something and leaving the player, the tabs still answer.
    func testTabsAfterLeavingThePlayer() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockMedia", PlayerTests.media, "-reset", "-autoplay", "media-1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 8), "player didn't open")
        Thread.sleep(forTimeInterval: 1)
        let remote = XCUIRemote.shared
        for _ in 0..<3 where app.staticTexts["player.time"].exists {    // hide controls, then leave
            remote.press(.menu)
            Thread.sleep(forTimeInterval: 0.8)
        }
        XCTAssertFalse(app.staticTexts["player.time"].exists, "couldn't leave the player")
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(focusedDescription(app).hasPrefix("TABBAR"), "After the player, Up: focus on \(focusedDescription(app))")
    }

    /// A real server's spread of libraries (two books libraries, collections,
    /// playlists, home videos) and two more: every tab is on the bar.
    func testEveryLibraryTabFits() {
        let app = launchHome(["-mockLibraries", "Books:books,Collections:boxsets,Playlists:playlists,Videos:homevideos,Kids:movies,Anime:tvshows"])
        XCUIRemote.shared.press(.up)
        Thread.sleep(forTimeInterval: 1)
        let window = app.windows.firstMatch.frame
        let tabs = app.descendants(matching: .any).matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.button.rawValue)).allElementsBoundByIndex
            .filter { $0.frame.maxY < 170 && $0.frame.width > 0 }
        print("TABBAR-DEBUG tabs: \(tabs.map { "'\($0.label)'" }.joined(separator: " "))")
        XCTAssertGreaterThanOrEqual(tabs.count, 5, "too few tabs on the bar")
        for t in tabs { XCTAssertTrue(window.contains(t.frame), "tab '\(t.label)' runs off the screen") }
    }
}
