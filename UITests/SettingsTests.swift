import XCTest

/// Settings: one page, reached from the tab bar; switches flip where they
/// are and choices open under their section.
@MainActor
final class SettingsTests: XCTestCase {
    /// From the Settings tab, a switch flips in place.
    func testSwitchFlipsInPlaceFromSettingsTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].exists(within: 5))
        let remote = XCUIRemote.shared
        app.focusSettles()
        remote.press(.menu, movingFocusIn: app)               // content → the tabs (on Home)
        let settingsTab = app.buttons["gearshape"]
        XCTAssertTrue(settingsTab.exists(within: 2), "no Settings tab")
        remote.press(.right, in: app, atMost: 6) { settingsTab.hasFocus }   // along to Settings
        let autoplay = app.buttons["setting.autoplay"]
        XCTAssertTrue(autoplay.exists(within: 3), "Settings didn't open")
        remote.press(.down, movingFocusIn: app)               // the tabs → the page
        // Steer toward the tile: down while above it, left while beside it.
        let focused = app.focused
        for _ in 0..<10 where !autoplay.hasFocus {
            remote.press(focused.frame.maxY < autoplay.frame.minY ? .down : .left, movingFocusIn: app)
        }
        XCTAssertTrue(autoplay.hasFocus, "couldn't reach Play Next Episode")
        let before = autoplay.value as? String
        remote.press(.select)
        autoplay.wait { $0.value as? String != before }
        XCTAssertNotEqual(autoplay.value as? String, before, "the switch didn't flip")
        XCTAssertTrue(autoplay.hasFocus, "focus left the switch")
    }

    /// A choice opens its options under the section; picking one applies it,
    /// closes the row and puts focus back on the tile.
    func testChoiceOpensInlineAndApplies() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "settings:picture"]
        app.launch()
        let bitrate = app.buttons["setting.bitrate"]
        XCTAssertTrue(bitrate.exists(within: 5))
        let remote = XCUIRemote.shared
        app.focusSettles()                                    // the page scrolled to its section
        let focused = app.focused
        for _ in 0..<16 where !bitrate.hasFocus {
            remote.press(focused.identifier == "setting.engine" ? .right : .down, movingFocusIn: app)      // down to Player, then across
        }
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/settings-nav.png"))
        }
        XCTAssertTrue(bitrate.hasFocus, "couldn't reach Maximum Bitrate")
        remote.press(.select)
        let option = app.buttons["setting.bitrate.20000000"]
        XCTAssertTrue(option.exists(within: 2), "no options row")
        app.focusSettles()                                    // the row opened under its section
        remote.press(.right, in: app, atMost: 6) { option.hasFocus }
        XCTAssertTrue(option.hasFocus, "couldn't reach 20 Mbps")
        remote.press(.select)
        bitrate.wait { $0.hasFocus && $0.value as? String == "20 Mbps" }
        XCTAssertEqual(bitrate.value as? String, "20 Mbps")
        XCTAssertFalse(option.exists, "the options row didn't close")
        XCTAssertTrue(bitrate.hasFocus, "focus didn't come back to the tile")
    }
}
