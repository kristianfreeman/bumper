import XCTest

/// Settings → Libraries: every library on the server, where it is, and a
/// switch that takes one out of the app.
@MainActor
final class PhoneLibrariesTests: XCTestCase {
    func testHidingALibraryTakesItsTabAway() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-mockLibraries", "Audiobooks:books,Books:books,Collections:boxsets,Playlists:playlists,Videos:homevideos",
                               "-route", "settings:libraries"]
        app.launch()
        let videosTab = app.tabBars.buttons["Videos"]
        XCTAssertTrue(videosTab.waitForExistence(timeout: 10), "no Videos tab to begin with")
        XCTAssertTrue(app.staticTexts["Playlists aren't supported yet"].waitForExistence(timeout: 3), "the libraries it can't play aren't listed")
        let toggle = app.switches["setting.library.view-extra-videos"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "no switch for Videos")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(videosTab.waitForNonExistence(timeout: 3), "hiding Videos left its tab")
        XCTAssertTrue(app.staticTexts["Hidden"].exists, "Videos doesn't say it's hidden")
    }
}
