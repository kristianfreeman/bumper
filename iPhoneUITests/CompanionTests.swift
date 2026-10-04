import XCTest

/// The companion, against the Apple TV app running in the tvOS simulator on
/// the same Mac (`scripts/companion-check.sh` starts it, on a detail page).
@MainActor
final class CompanionTests: XCTestCase {
    /// Finds the TV, shows what's focused on it, and adds it to Tonight —
    /// which comes back from the TV as a Tonight entry.
    func testMirrorsTheTVAndPlansTonight() {
        let app = XCUIApplication()
        app.launch()
        let expected = ProcessInfo.processInfo.environment["EXPECT_TITLE"] ?? "Endless Voyage"
        let shown = app.staticTexts.matching(NSPredicate(format: "label == %@", expected))
        XCTAssertTrue(shown.firstMatch.waitForExistence(timeout: 20), "the TV's focused title (\(expected)) never appeared — not connected?")
        let add = app.buttons["phone.addFocused"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        // It comes back from the TV as a Tonight entry: the title twice on screen.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, shown.count < 2 { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertGreaterThanOrEqual(shown.count, 2, "Tonight on the phone didn't show the added title")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/companion.png"))
        }
    }
}
