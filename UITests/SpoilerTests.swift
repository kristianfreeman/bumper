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
        XCTAssertTrue(reveal.waitForExistence(timeout: 10), "the description isn't blurred")
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !reveal.hasFocus { remote.press(.up); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(reveal.hasFocus, "couldn't reach the blurred description")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/spoiler-focused.png"))
        }
        remote.press(.select)
        let gone = Date().addingTimeInterval(3)
        while Date() < gone, reveal.exists { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertFalse(reveal.exists, "Select didn't show the description")
    }
}
