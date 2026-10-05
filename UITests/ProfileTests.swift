import XCTest

/// Home's top-right profile corner. Its own class (and `scripts/test.sh
/// profile` tier) so every UI run stays inside the 30 s cap.
@MainActor
final class ProfileTests: XCTestCase {
    /// Top-right corner (icon pills): up from the cards reaches the avatar;
    /// the sleep timer sets from its pill; selecting the avatar opens the profile.
    func testProfileMenuAndSleepTimer() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        let avatar = app.buttons["profile.avatar"]
        for _ in 0..<3 { remote.press(.right) }      // rightmost card…
        remote.press(.up)                            // …then up into the corner
        XCTAssertTrue(avatar.waitForExistence(timeout: 2))
        XCTAssertTrue(avatar.hasFocus, "Up from the right-hand cards should reach the avatar")

        let sleep = app.buttons["profile.sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 1), "No sleep timer pill")
        remote.press(.left)
        XCTAssertTrue(sleep.hasFocus)
        remote.press(.select)
        let fifteen = app.buttons["15 Minutes"]
        XCTAssertTrue(fifteen.waitForExistence(timeout: 2), "Sleep options didn't appear")
        // Focus starts on the first option.
        remote.press(.select)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !["15m", "14m"].contains(sleep.value as? String ?? "") { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertTrue(["15m", "14m"].contains(sleep.value as? String ?? ""), "Timer not shown on its pill (\(sleep.value ?? "nil"))")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "profile-menu"
        shot.lifetime = .keepAlways
        add(shot)
        remote.press(.right)                         // back to the avatar
        remote.press(.select)
        // Not the first tile's label: focus lands on that tile as the page
        // opens, and while it's focused it drops out of the accessibility tree.
        XCTAssertTrue(app.staticTexts["Episodes watched"].waitForExistence(timeout: 3), "Profile didn't open")
    }
}
