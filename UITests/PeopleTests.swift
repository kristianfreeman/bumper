import XCTest

/// People and trailers on the TV: getting there with focus and the remote.
/// What the pages show (the cast in order, a person's films and what
/// they're known for, trailers and extras that play) is checked in-process:
/// AppFeaturesTests' People. In the mock, film 3 only has a trailer online,
/// which the TV can't play.
@MainActor
final class PeopleTests: XCTestCase {
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func focused(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }

    /// Down to the cast, open one: their page, with their films and shows;
    /// one of those opens its page, and Menu comes back to them.
    func testACastCardOpensTheirPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 10), "no detail page")
        let remote = XCUIRemote.shared
        let focus = focused(app)
        // Past the actions and the extras to the cast.
        for _ in 0..<6 where !focus.identifier.hasPrefix("person.") { remote.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(focus.identifier.hasPrefix("person."), "couldn't reach the cast (focus: \(focus.identifier))")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["person.name"].waitForExistence(timeout: 5), "the cast card didn't open their page")
        let titles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.item.'"))
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 5), "no films or shows on their page")
        Thread.sleep(forTimeInterval: 0.6)
        shot("person")
        for _ in 0..<3 where !focus.identifier.hasPrefix("person.item.") { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(focus.identifier.hasPrefix("person.item."), "focus isn't on their films (focus: \(focus.identifier))")
        let opened = focus.identifier
        remote.press(.select)
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 5), "their film didn't open")
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(focus.identifier, opened, "Menu didn't come back to their page")
    }

    /// Film 3's trailer is only online, so the TV (no browser, no YouTube
    /// app) shows no button; elsewhere it's a link.
    func testNoTrailerButtonForOneOnlyOnline() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0003"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 10), "no detail page")
        Thread.sleep(forTimeInterval: 1.5)                              // trailers and extras arrive after the page
        XCTAssertFalse(app.buttons["detail.trailer"].exists, "a Trailer button for a trailer only online")
    }
}
