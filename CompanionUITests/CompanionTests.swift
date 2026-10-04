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
        let title = app.staticTexts["phone.focusedTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "never connected to the TV, or nothing focused there")
        let expected = ProcessInfo.processInfo.environment["EXPECT_TITLE"] ?? ""
        if !expected.isEmpty { XCTAssertEqual(title.label, expected) }
        let add = app.buttons["phone.addFocused"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        let entry = app.staticTexts.matching(NSPredicate(format: "label == %@", title.label)).element(boundBy: 1)
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Tonight on the phone didn't show the added title")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/companion.png"))
        }
    }
}
