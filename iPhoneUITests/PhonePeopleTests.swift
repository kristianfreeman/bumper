import XCTest

/// People, trailers and extras on the iPhone. In the mock, film 1 has a
/// trailer in the library, one online and four extras; film 2 has none;
/// film 3 only a trailer online (it opens YouTube or the browser here).
@MainActor
final class PhonePeopleTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Scrolls the page until `element` can be tapped, then lets the scroll
    /// come to rest: a tap while the page is still gliding only stops it
    /// (the extra's tap did nothing, now and then).
    private func reach(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        var swiped = false
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
            swiped = true
        }
        if swiped { Thread.sleep(forTimeInterval: 1) }
        return element.exists && element.isHittable
    }

    /// A cast card opens their page; one of their films opens its page; Back returns.
    func testACastCardOpensTheirPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 10), "no detail page")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5) && reach(card, in: app), "no cast to tap")
        card.tap()
        XCTAssertTrue(app.staticTexts["person.name"].waitForExistence(timeout: 5), "the cast card didn't open their page")
        XCTAssertTrue(app.staticTexts["person.knownFor"].exists, "no line saying what they're known for")
        let title = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.item.'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "no films or shows on their page")
        shot(app, "person")
        XCTAssertTrue(reach(title, in: app), "can't reach their films")
        title.tap()
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 5), "their film didn't open")
        let back = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), "no way back")
        back.tap()
        XCTAssertTrue(app.staticTexts["person.name"].waitForExistence(timeout: 3), "Back didn't return to their page")
    }

    /// Film 1: a Trailer button and the Extras row, whose cards play.
    func testAFilmWithExtrasShowsThem() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.trailer"].waitForExistence(timeout: 10), "no Trailer button")
        let extra = app.buttons["extra.movie-0001-extra-1"]
        XCTAssertTrue(extra.waitForExistence(timeout: 5) && reach(extra, in: app), "no Extras row")
        shot(app, "detail-extras")
        extra.tap()
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 10), "the extra didn't play")
    }

    /// Film 3's trailer is only online: here it's still a button (not
    /// pressed: it would leave the app). Film 2 has neither.
    func testTrailersOnlineShowHere() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0003"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.trailer"].waitForExistence(timeout: 10), "no Trailer button for a trailer online")
        app.terminate()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0002"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 10), "no detail page")
        Thread.sleep(forTimeInterval: 1.5)                                  // trailers and extras arrive after the page
        XCTAssertFalse(app.buttons["detail.trailer"].exists, "a Trailer button with no trailer")
        XCTAssertFalse(app.buttons["extra.movie-0002-extra-1"].exists, "extras where there are none")
    }
}
