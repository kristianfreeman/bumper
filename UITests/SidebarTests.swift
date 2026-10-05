import XCTest

/// The tab sidebar opens from content, both ways people open it.
@MainActor
final class SidebarTests: XCTestCase {
    func focusedDescription(_ app: XCUIApplication) -> String {
        let f = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        guard f.exists else { return "nothing" }
        // Sidebar items carry no label: recognise them by where they are.
        let inSidebar = f.frame.minX < 450 && f.frame.maxY < 500 && f.frame.width < 450
        return "\(inSidebar ? "SIDEBAR " : "")\(f.elementType.rawValue) '\(f.label)' \(Int(f.frame.minX)),\(Int(f.frame.minY)) \(Int(f.frame.width))x\(Int(f.frame.height))"
    }

    /// Left from the first card, and Menu, both put focus in the sidebar —
    /// with every kind of library present (Audiobooks adds its own tab).
    func testSidebarOpensFromHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockMedia", PlayerTests.media, "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        let content = focusedDescription(app)
        XCUIRemote.shared.press(.left)
        Thread.sleep(forTimeInterval: 0.8)
        let afterLeft = focusedDescription(app)
        print("SIDEBAR-DEBUG content=\(content) afterLeft=\(afterLeft)")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/sidebar-open.png"))
        }
        XCTAssertNotEqual(afterLeft, content, "Left from the first card didn't leave the row")
        XCTAssertTrue(afterLeft.hasPrefix("SIDEBAR"), "Left from the first card: focus on \(afterLeft), not the sidebar")

        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 0.8)
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 0.8)
        let afterMenu = focusedDescription(app)
        print("SIDEBAR-DEBUG afterMenu=\(afterMenu)")
        XCTAssertTrue(afterMenu.hasPrefix("SIDEBAR"), "Menu: focus on \(afterMenu), not the sidebar")
    }

    /// After watching something and leaving the player, the sidebar still
    /// opens (the player's remote handling must not outlive it).
    func testSidebarOpensAfterLeavingThePlayer() {
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
        remote.press(.left)
        Thread.sleep(forTimeInterval: 0.8)
        let afterLeft = focusedDescription(app)
        print("SIDEBAR-DEBUG after player: \(afterLeft)")
        XCTAssertTrue(afterLeft.hasPrefix("SIDEBAR"), "After the player, Left: focus on \(afterLeft)")
    }

    /// From lower rows (the rows above are hidden) and from a library page.
    func testSidebarOpensFromLowerRowsAndLibraries() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        remote.press(.down); remote.press(.down)
        Thread.sleep(forTimeInterval: 0.8)
        let row3 = focusedDescription(app)
        remote.press(.left)
        Thread.sleep(forTimeInterval: 0.8)
        let fromRow3 = focusedDescription(app)
        print("SIDEBAR-DEBUG row 3 was \(row3)")
        print("SIDEBAR-DEBUG row 3: \(fromRow3)")
        XCTAssertTrue(fromRow3.hasPrefix("SIDEBAR"), "From the third row, Left: focus on \(fromRow3)")

        remote.press(.down)                                   // Home → Movies
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.select)
        Thread.sleep(forTimeInterval: 2)
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.8)
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 0.8)
        if !focusedDescription(app).hasPrefix("SIDEBAR") { remote.press(.menu); Thread.sleep(forTimeInterval: 0.8) }   // back to the top first
        let fromLibrary = focusedDescription(app)
        print("SIDEBAR-DEBUG library menu: \(fromLibrary)")
        XCTAssertTrue(fromLibrary.hasPrefix("SIDEBAR"), "From Movies, Menu: focus on \(fromLibrary)")
    }

    /// From a card in the first row (where people are when they press Menu):
    /// Menu, and Left from the first card, open the sidebar.
    func testSidebarOpensFromAFocusedCard() {
        let app = XCUIApplication()
        // A real server's libraries (two books libraries, collections, home
        // videos) plus two more: past seven sidebar entries tvOS's sidebar
        // stops opening, so the app must fold them. EXTRA_ARGS adds more.
        let extra = (ProcessInfo.processInfo.environment["EXTRA_ARGS"] ?? "").split(separator: " ").map(String.init)
        app.launchArguments = ["-mock", "-reset", "-mockLibraries", "Books:books,Collections:boxsets,Playlists:playlists,Videos:homevideos,Kids:movies,Anime:tvshows"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        let remote = XCUIRemote.shared
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        for _ in 0..<3 where focused.frame.minY < 400 { remote.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        let onCard = focusedDescription(app)
        print("SIDEBAR-DEBUG on card: \(onCard)")
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        let afterMenu = focusedDescription(app)
        print("SIDEBAR-DEBUG card → menu: \(afterMenu)")
        XCTAssertTrue(afterMenu.hasPrefix("SIDEBAR"), "Menu from \(onCard): focus on \(afterMenu)")
        remote.press(.right)
        Thread.sleep(forTimeInterval: 1)
        var presses = 0
        while presses < 6, !focusedDescription(app).hasPrefix("SIDEBAR") {
            remote.press(.left)
            presses += 1
            Thread.sleep(forTimeInterval: 0.4)
        }
        let reached = focusedDescription(app)
        Thread.sleep(forTimeInterval: 2)                      // and it stays there
        let afterLeft = focusedDescription(app)
        print("SIDEBAR-DEBUG card → left ×\(presses): \(reached) → 2 s later \(afterLeft)")
        XCTAssertTrue(afterLeft.hasPrefix("SIDEBAR"), "Left from the first card: focus on \(afterLeft) (reached \(reached))")
        // The menu route, from a card again, must stay open too.
        remote.press(.right)
        Thread.sleep(forTimeInterval: 1)
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 2)
        let menuStays = focusedDescription(app)
        print("SIDEBAR-DEBUG card → menu, 2 s later: \(menuStays)")
        XCTAssertTrue(menuStays.hasPrefix("SIDEBAR"), "Menu: 2 s later focus on \(menuStays)")
    }

    /// Same, from the third row (nothing under the sidebar's lower half).
    func testSidebarOpensFromALowerRow() {
        let app = XCUIApplication()
        let extra = (ProcessInfo.processInfo.environment["EXTRA_ARGS"] ?? "").split(separator: " ").map(String.init)
        app.launchArguments = ["-mock", "-reset"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        let remote = XCUIRemote.shared
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        for _ in 0..<3 where focused.frame.minY < 400 { remote.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        remote.press(.down); remote.press(.down)
        Thread.sleep(forTimeInterval: 1)
        let onCard = focusedDescription(app)
        // Scrolled down, Menu first goes back to the top (as in Apple's TV
        // app); the next one opens the sidebar.
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        if !focusedDescription(app).hasPrefix("SIDEBAR") { remote.press(.menu) }
        Thread.sleep(forTimeInterval: 2)
        let after = focusedDescription(app)
        print("SIDEBAR-DEBUG lower row \(onCard) → menu: \(after)")
        XCTAssertTrue(after.hasPrefix("SIDEBAR"), "Menu from \(onCard): focus on \(after)")
    }

    /// Up from the top row: the left half goes to the sidebar's tab button,
    /// the right half to the profile pills.
    func testUpFromTheTopRowReachesTheSidebarOrTheProfile() throws {
        // tvOS 26's collapsed sidebar has no focusable item: only Left and Menu open it.
        if #unavailable(tvOS 27.0) { throw XCTSkip("Up can't reach the sidebar before tvOS 27") }
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        let remote = XCUIRemote.shared
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.8)
        let leftUp = focusedDescription(app)
        print("SIDEBAR-DEBUG up from first card: \(leftUp)")
        XCTAssertTrue(leftUp.hasPrefix("SIDEBAR"), "Up from the first card: focus on \(leftUp)")
        remote.press(.right)                                           // sidebar → back to the cards
        Thread.sleep(forTimeInterval: 0.8)
        remote.press(.right); remote.press(.right)                     // third card: the right half
        Thread.sleep(forTimeInterval: 0.6)
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.8)
        let rightUp = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        print("SIDEBAR-DEBUG up from third card: \(rightUp.identifier) '\(rightUp.label)'")
        XCTAssertTrue(rightUp.identifier.hasPrefix("profile."), "Up from the right half: focus on \(rightUp.identifier) '\(rightUp.label)'")
    }

    /// With Tonight leading Home, its controls sit top right: Up from the
    /// left half still goes to the sidebar.
    func testUpFromTonightReachesTheSidebar() throws {
        // tvOS 26's collapsed sidebar has no focusable item: only Left and Menu open it.
        if #unavailable(tvOS 27.0) { throw XCTSkip("Up can't reach the sidebar before tvOS 27") }
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        let add = app.buttons["detail.tonight"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !add.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.menu)
        XCTAssertTrue(app.descendants(matching: .any)["collection.tonight"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.2)
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'card.tonight.'")).firstMatch
        for _ in 0..<4 where !card.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        for _ in 0..<4 where !card.hasFocus { remote.press(.up); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(card.hasFocus, "couldn't reach the Tonight card (focus: \(focusedDescription(app)))")
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.8)
        let up = focusedDescription(app)
        XCTAssertTrue(up.hasPrefix("SIDEBAR"), "Up from the Tonight card: focus on \(up)")
    }
}
