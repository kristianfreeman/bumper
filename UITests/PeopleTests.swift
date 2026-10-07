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
        Thread.sleep(forTimeInterval: 0.6)                              // a still screen, for the picture
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
        XCTAssertTrue(app.buttons["detail.play"].exists(within: 10), "no detail page")
        let remote = XCUIRemote.shared
        let focus = focused(app)
        // Past the actions and the extras to the cast.
        remote.press(.down, in: app, atMost: 6) { focus.identifier.hasPrefix("person.") }
        XCTAssertTrue(focus.identifier.hasPrefix("person."), "couldn't reach the cast (focus: \(focus.identifier))")
        let card = focus.identifier
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["person.name"].exists(within: 5), "the cast card didn't open their page")
        let titles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.item.'"))
        XCTAssertTrue(titles.firstMatch.exists(within: 5), "no films or shows on their page")
        // Their page pushed in: focus over on it (it stays on the card a
        // moment), and done moving. A press before then went nowhere.
        waitUntil(3) { focus.identifier != card }
        app.focusSettles()
        shot("person")
        remote.press(.down, in: app, atMost: 3) { focus.identifier.hasPrefix("person.item.") }
        XCTAssertTrue(focus.identifier.hasPrefix("person.item."), "focus isn't on their films (focus: \(focus.identifier))")
        app.focusSettles(quiet: 0.2)
        let opened = focus.identifier
        remote.press(.select)
        XCTAssertTrue(app.buttons["detail.play"].exists(within: 5), "their film didn't open")
        remote.press(.menu)
        waitUntil(3) { focus.identifier == opened }
        XCTAssertEqual(focus.identifier, opened, "Menu didn't come back to their page")
    }

    /// Film 3's trailer is only online, so the TV (no browser, no YouTube
    /// app) shows no button; elsewhere it's a link.
    func testNoTrailerButtonForOneOnlyOnline() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0003"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.play"].exists(within: 10), "no detail page")
        // Trailers and extras arrive after the page, with More Like This.
        XCTAssertTrue(app.staticTexts["More Like This"].exists(within: 5), "the page didn't finish loading")
        Thread.sleep(forTimeInterval: 0.3)                              // (the extras' answer comes with it)
        XCTAssertFalse(app.buttons["detail.trailer"].exists, "a Trailer button for a trailer only online")
    }
}
