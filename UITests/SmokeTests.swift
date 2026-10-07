import XCTest

/// Fast functional checks of the main flows against the mock server.
@MainActor
final class SmokeTests: XCTestCase {
    func testDetailAndBackToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5), "Detail page has no Play button")
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        if !play.hasFocus { print("FOCUS-TREE-BEGIN\n\(app.debugDescription)\nFOCUS-TREE-END") }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(play.hasFocus, "Play should take default focus on the detail page; focus is on: \(focused.exists ? "\(focused.elementType.rawValue) '\(focused.label)' id=\(focused.identifier)" : "nothing")")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5), "Back didn't return to Home")
    }

    /// Down moves to the next row (the one above fades out), Up comes back —
    /// the hidden row must still take focus.
    func testRowsMoveDownAndBackUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5) && focused.waitForExistence(timeout: 5))
        let first = focused.identifier + focused.label
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        let second = focused.identifier + focused.label
        XCTAssertNotEqual(first, second, "Down didn't move focus to the next row")
        XCUIRemote.shared.press(.up)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(focused.identifier + focused.label, first, "Up didn't return to the row above")
    }

    func testHomeShowsContentFocused() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        // First thing focused on launch should be content, not the tab bar.
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        XCTAssertTrue(focused.waitForExistence(timeout: 5))
        // Sidebar items are cells; content cards are buttons.
        XCTAssertNotEqual(focused.elementType, .cell, "Launch focus landed on the tab sidebar (\(focused.label))")
    }

    /// Resting on a card prefetches its details, so the page opens fully drawn.
    func testFocusedCardIsPrefetchedBeforeOpening() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-quickTimers", "-reset", "-perfHUD"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        for _ in 0..<8 where !focused.identifier.hasPrefix("card.latest-movies") {   // down to the first film
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(focused.identifier.hasPrefix("card.latest-movies"), "never reached the films (focus: \(focused.identifier))")
        Thread.sleep(forTimeInterval: 0.3)   // rest on the card (dwell: 350 ms, 70 at -quickTimers' pace)
        remote.press(.select)
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        let metrics = try PerformanceTests.readMetrics(app)
        XCTAssertEqual(metrics["detail.prefetchHit"]?["last"], 1, "Detail page didn't open from the prefetch")
    }

    func testOnboardingWithoutMock() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.network"].waitForExistence(timeout: 5))
    }

    /// Pick the server, see the profiles and the Quick Connect code; the mock
    /// approves the code after a couple of polls and the TV signs in on its own.
    func testOnboardingSignsInWithQuickConnect() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockOnboarding", "-reset"]
        // TEST_RUNNER_THEME=<id>: screenshots in another theme.
        if let theme = ProcessInfo.processInfo.environment["THEME"] { app.launchArguments += ["-appearance.theme", theme] }
        app.launch()
        let server = app.buttons["onboarding.server.mock-server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5), "the mock server isn't listed")
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !server.hasFocus { remote.press(.up); Thread.sleep(forTimeInterval: 0.3) }
        shot(app, "onboarding-connect")
        remote.press(.select)
        let code = app.descendants(matching: .any)["quickconnect.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5), "no Quick Connect code")
        XCTAssertTrue(app.buttons["onboarding.user.Tester"].exists, "no profiles")
        shot(app, "onboarding-signin")
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 12), "Quick Connect didn't sign in")
    }

    /// Select on something in progress resumes it; hold, then Select on the
    /// first item (See Details) opens its page instead.
    func testHoldOpensDetailsForThingsThatPlay() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        let remote = XCUIRemote.shared
        remote.press(.select, forDuration: 1.2)
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'See Details'")).firstMatch
        if !details.waitForExistence(timeout: 3) {
            XCTFail("holding didn't open the menu with See Details; menu: \(app.descendants(matching: .any).matching(NSPredicate(format: "elementType == 6 OR elementType == 9")).allElementsBoundByIndex.prefix(12).map(\.label))")
            return
        }
        Thread.sleep(forTimeInterval: 0.4)
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        print("MENU-DEBUG focused: \(focused.elementType.rawValue) '\(focused.label)'")
        remote.press(.select)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume' OR label BEGINSWITH 'Play'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "See Details didn't open the page")
        XCTAssertFalse(app.descendants(matching: .any)["player.time"].exists, "it played instead of opening the page")
    }

    /// The Top Shelf's links: bumper://play/<id> opens straight into the player.
    func testTopShelfLinkPlays() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 8))
        app.open(URL(string: "bumper://play/movie-0001")!)
        // The simulator asks first ("Open in Bumper?"); the Top Shelf doesn't.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { XCUIRemote.shared.press(.select) }
        XCTAssertTrue(app.descendants(matching: .any)["player.time"].waitForExistence(timeout: 8), "the link didn't start playback")
    }

    /// The Top Shelf's Browse tiles: bumper://search opens Search, bumper://queue the plan.
    func testTopShelfLinksOpenPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 8))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
        app.open(URL(string: "bumper://search")!)
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { XCUIRemote.shared.press(.select) }
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "bumper://search didn't open Search")
        app.open(URL(string: "bumper://queue")!)
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { XCUIRemote.shared.press(.select) }
        XCTAssertTrue(app.staticTexts["Queue"].waitForExistence(timeout: 5), "bumper://queue didn't open the plan")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        Thread.sleep(forTimeInterval: 1.2)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
