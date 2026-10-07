import XCTest

/// Settings → Libraries: every library it can play, where it is, and a
/// switch that takes one out of the app (the ones it can't aren't listed).
@MainActor
final class PhoneLibrariesTests: XCTestCase {
    func testHidingALibraryTakesItsTabAway() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-mockLibraries", "Audiobooks:books,Books:books,Collections:boxsets,Playlists:playlists,Videos:homevideos",
                               "-route", "settings:libraries"]
        app.launch()
        let videosTab = app.tabBars.buttons["Videos"]
        XCTAssertTrue(videosTab.exists(within: 10), "no Videos tab to begin with")
        XCTAssertTrue(app.switches["setting.library.view-extra-videos"].exists(within: 3), "the libraries aren't listed")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'supported'")).firstMatch.exists, "a library it can't play is listed")
        let toggle = app.switches["setting.library.view-extra-videos"]
        XCTAssertTrue(toggle.exists(within: 3), "no switch for Videos")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(videosTab.gone(within: 3), "hiding Videos left its tab")
        XCTAssertTrue(app.staticTexts["Hidden"].exists, "Videos doesn't say it's hidden")
    }
}
