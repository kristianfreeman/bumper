import XCTest

/// An unwatched episode's description is blurred (Hide Spoilers); focus it
/// and press Select, and it shows — until the page goes.
@MainActor
final class SpoilerTests: XCTestCase {
    func testSelectRevealsABlurredDescription() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-route", "item:series-001-s2-e5"]      // an unwatched episode
        app.launch()
        let reveal = app.buttons["spoiler.reveal"]
        XCTAssertTrue(reveal.exists(within: 10), "the description isn't blurred")
        let remote = XCUIRemote.shared
        remote.press(.up, in: app, atMost: 4) { reveal.hasFocus }
        XCTAssertTrue(reveal.hasFocus, "couldn't reach the blurred description")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/spoiler-focused.png"))
        }
        remote.press(.select)
        reveal.gone(within: 3)
        XCTAssertFalse(reveal.exists, "Select didn't show the description")
    }
}
