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
        app.launchArguments = ["-mock", "-reset", "-perfHUD"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        for _ in 0..<8 where !focused.identifier.hasPrefix("card.latest-movies") {   // down to the first film
            remote.press(.down)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(focused.identifier.hasPrefix("card.latest-movies"), "never reached the films (focus: \(focused.identifier))")
        Thread.sleep(forTimeInterval: 0.8)   // rest on the card (dwell = 350 ms)
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
        XCTAssertTrue(app.staticTexts["On Your Network"].waitForExistence(timeout: 5))
    }
}
