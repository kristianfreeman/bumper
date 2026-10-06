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
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        remote.press(.menu)                                   // content → the tabs (on Home)
        Thread.sleep(forTimeInterval: 0.8)
        let settingsTab = app.buttons["gearshape"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 2), "no Settings tab")
        for _ in 0..<6 where !settingsTab.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.4) }   // along to Settings
        let autoplay = app.buttons["setting.autoplay"]
        XCTAssertTrue(autoplay.waitForExistence(timeout: 3), "Settings didn't open")
        remote.press(.down)                                   // the tabs → the page
        // Steer toward the tile: down while above it, left while beside it.
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        for _ in 0..<10 where !autoplay.hasFocus {
            remote.press(focused.frame.maxY < autoplay.frame.minY ? .down : .left)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(autoplay.hasFocus, "couldn't reach Play Next Episode")
        let before = autoplay.value as? String
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.5)
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
        XCTAssertTrue(bitrate.waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        Thread.sleep(forTimeInterval: 1)
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        for _ in 0..<16 where !bitrate.hasFocus {
            print("SETTINGS-DEBUG focus \(focused.identifier) '\(focused.label)' \(focused.frame)")
            remote.press(focused.identifier == "setting.engine" ? .right : .down)      // down to Player, then across
            Thread.sleep(forTimeInterval: 0.35)
        }
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/settings-nav.png"))
        }
        XCTAssertTrue(bitrate.hasFocus, "couldn't reach Maximum Bitrate")
        remote.press(.select)
        let option = app.buttons["setting.bitrate.20000000"]
        XCTAssertTrue(option.waitForExistence(timeout: 2), "no options row")
        Thread.sleep(forTimeInterval: 0.6)
        for _ in 0..<6 where !option.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(option.hasFocus, "couldn't reach 20 Mbps")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(bitrate.value as? String, "20 Mbps")
        XCTAssertFalse(option.exists, "the options row didn't close")
        XCTAssertTrue(bitrate.hasFocus, "focus didn't come back to the tile")
    }
}
