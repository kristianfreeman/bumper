import XCTest

/// Settings, reached the way people reach it: the sidebar's Settings tab.
@MainActor
final class SettingsTests: XCTestCase {
    /// Selecting a row inside the Settings *tab* opens its page. (View-based
    /// links lost their navigation stack inside a tab and did nothing.)
    func testRowOpensPageFromSettingsTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        remote.press(.menu)                                   // content → sidebar (on Home)
        XCTAssertTrue(app.buttons["gearshape"].waitForExistence(timeout: 2), "Sidebar didn't open")
        for _ in 0..<4 { remote.press(.down) }                // Home → Movies → TV Shows → Search → Settings
        remote.press(.select)
        let playback = app.buttons["settings.playback"]
        XCTAssertTrue(playback.waitForExistence(timeout: 3))
        remote.press(.right)                                  // sidebar → the list (first row: Playback)
        remote.press(.select)
        XCTAssertTrue(app.buttons["settings.bitrate"].waitForExistence(timeout: 3), "Selecting Playback didn't open its page")
    }
}
