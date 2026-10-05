import XCTest

/// The player's layout on the iPhone, portrait and landscape (screenshots
/// for review; asserts only that it plays and the controls are on screen).
@MainActor
final class PhonePlayerLayoutTests: XCTestCase {
    static let media = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "TestMedia/long").path

    func testPlayerLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-reset", "-mockMedia", Self.media, "-autoplay", ProcessInfo.processInfo.environment["ITEM"] ?? "media-0"]
        app.launch()
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 10))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1.5)
            app.otherElements["player.surface"].firstMatch.tap()            // controls on (or off, then on)
            Thread.sleep(forTimeInterval: 0.6)
            if !app.buttons["player.close"].exists { app.otherElements["player.surface"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.6) }
            shot(app, "player-\(orientation == .portrait ? "portrait" : "landscape")-chrome")
            let close = app.buttons["player.close"]
            if close.exists { XCTAssertTrue(app.windows.firstMatch.frame.contains(close.frame), "Close is off screen in \(orientation.rawValue)") }
            app.otherElements["player.surface"].firstMatch.tap()            // controls off: the picture alone
            Thread.sleep(forTimeInterval: 0.8)
            shot(app, "player-\(orientation == .portrait ? "portrait" : "landscape")-clean")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
