import XCTest

/// People on the iPhone: swiping to the cast and their films, and Back.
/// What the pages show (trailers, extras, a trailer online as a link) is
/// checked in-process: AppFeaturesTests' People.
@MainActor
final class PhonePeopleTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Scrolls the page until `element` can be tapped, then lets the scroll
    /// come to rest (it stays put between two looks): a tap while the page
    /// is still gliding only stops it (the extra's tap did nothing, now and
    /// then).
    private func reach(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        var swiped = false
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
            swiped = true
        }
        if swiped { element.settles() }
        return element.exists && element.isHittable
    }

    /// A cast card opens their page; one of their films opens its page; Back returns.
    func testACastCardOpensTheirPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.play"].exists(within: 10), "no detail page")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.'")).firstMatch
        XCTAssertTrue(card.exists(within: 5) && reach(card, in: app), "no cast to tap")
        card.tap()
        XCTAssertTrue(app.staticTexts["person.name"].exists(within: 5), "the cast card didn't open their page")
        XCTAssertTrue(app.staticTexts["person.knownFor"].exists, "no line saying what they're known for")
        let title = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person.item.'")).firstMatch
        XCTAssertTrue(title.exists(within: 5), "no films or shows on their page")
        shot(app, "person")
        XCTAssertTrue(reach(title, in: app), "can't reach their films")
        title.tap()
        XCTAssertTrue(app.buttons["detail.play"].exists(within: 5), "their film didn't open")
        let back = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(back.settles(), "no way back")
        back.tap()
        XCTAssertTrue(app.staticTexts["person.name"].exists(within: 3), "Back didn't return to their page")
    }
}
