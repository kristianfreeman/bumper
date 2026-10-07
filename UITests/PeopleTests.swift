import XCTest

/// People, trailers and extras on a film's page. In the mock, film 1 has a
/// trailer in the library, one online and four extras; film 2 has none;
/// film 3 only a trailer online, which the TV can't play.
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
        XCTAssertTrue(app.staticTexts["person.knownFor"].waitForExistence(timeout: 5), "no line saying what they're known for")
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

    /// Film 1: the Extras row (its cards play) and a Trailer button.
    func testAFilmWithExtrasShowsThem() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.trailer"].waitForExistence(timeout: 10), "no Trailer button")
        let remote = XCUIRemote.shared
        let focus = focused(app)
        for _ in 0..<4 where !focus.identifier.hasPrefix("extra.") { remote.press(.down); Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertTrue(focus.identifier.hasPrefix("extra."), "couldn't reach the extras (focus: \(focus.identifier))")
        XCTAssertTrue(app.staticTexts["Extras"].exists, "the row has no title")
        shot("detail-extras")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 10), "the extra didn't play")
    }

    /// The trailer in the library plays in the player.
    func testTheTrailerPlays() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        let trailer = app.buttons["detail.trailer"]
        XCTAssertTrue(trailer.waitForExistence(timeout: 10), "no Trailer button")
        let remote = XCUIRemote.shared
        for _ in 0..<6 where !trailer.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(trailer.hasFocus, "couldn't reach Trailer")
        shot("detail-trailer")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 10), "the trailer didn't play")
    }

    /// Film 2 has neither; film 3's trailer is only online, so the TV shows no button.
    func testNoTrailerOrExtrasWhereThereAreNone() {
        let app = XCUIApplication()
        for film in ["movie-0002", "movie-0003"] {
            app.launchArguments = ["-mock", "-reset", "-route", "item:\(film)"]
            app.launch()
            XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 10), "no detail page for \(film)")
            Thread.sleep(forTimeInterval: 1.5)                              // trailers and extras arrive after the page
            XCTAssertFalse(app.buttons["detail.trailer"].exists, "\(film) has a Trailer button")
            XCTAssertFalse(app.staticTexts["Extras"].exists, "\(film) has an Extras row")
            app.terminate()
        }
    }

    /// A person who acts and directs says both; their bio is there.
    func testAnActorWhoDirects() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "person:person-a02"]
        app.launch()
        let knownFor = app.staticTexts["person.knownFor"]
        XCTAssertTrue(knownFor.waitForExistence(timeout: 10), "no person page")
        let both = NSPredicate(format: "label CONTAINS 'Actor' AND label CONTAINS 'Director'")
        expectation(for: both, evaluatedWith: knownFor)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["person.bio"].exists, "no bio")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.item.'")).firstMatch.exists, "no films or shows")
        shot("person-actor-director")
    }
}
