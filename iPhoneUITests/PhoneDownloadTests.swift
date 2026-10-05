import XCTest

/// Downloads on the iPhone, against the mock server: Download on a film's
/// page → Downloaded; it's on the Downloads tab; removing it empties it.
@MainActor
final class PhoneDownloadTests: XCTestCase {
    func testDownloadAFilmAndRemoveIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        let download = app.buttons["detail.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 10), "no Download button on the film's page")
        download.tap()
        let done = app.buttons.matching(NSPredicate(format: "label == 'Downloaded'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 20), "never finished downloading (button: \(download.label))")
        shot(app, "detail-downloaded")

        // The Downloads tab lists it.
        app.terminate()
        app.launchArguments = ["-mock"]                                 // same downloads, Home first
        app.launch()
        let tab = app.tabBars.buttons["Downloads"].exists ? app.tabBars.buttons["Downloads"] : app.buttons["Downloads"]
        if !tab.waitForExistence(timeout: 8) { app.tabBars.buttons["More"].tap() }
        (tab.exists ? tab : app.staticTexts["Downloads"]).tap()
        let card = app.buttons["downloads.film.movie-0001"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the film isn't on the Downloads page")
        shot(app, "downloads-page")
        card.press(forDuration: 1.2)
        let remove = app.buttons["Remove Download"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "removing didn't take it off the page")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
