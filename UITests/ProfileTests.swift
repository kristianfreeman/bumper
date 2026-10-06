import XCTest

/// Home's top-right profile corner. Its own class (and `scripts/test.sh
/// profile` tier) so every UI run stays inside the 30 s cap.
@MainActor
final class ProfileTests: XCTestCase {
    /// Your profile is the tab bar's last tab: along the tabs to it, and it
    /// shows your numbers; the sleep timer isn't here (it's in the player).
    func testTheProfileTabShowsYourNumbers() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        remote.press(.up)
        Thread.sleep(forTimeInterval: 0.6)
        let profile = app.buttons["Tester"]
        for _ in 0..<8 where !profile.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(profile.hasFocus, "couldn't reach the profile tab")
        XCTAssertFalse(app.buttons["profile.sleep"].exists, "the sleep timer belongs in the player")
        // Not the first tile's label: focus lands on that tile as the page
        // opens, and while it's focused it drops out of the accessibility tree.
        XCTAssertTrue(app.staticTexts["Episodes watched"].waitForExistence(timeout: 3), "Profile didn't open")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "profile-tab"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
