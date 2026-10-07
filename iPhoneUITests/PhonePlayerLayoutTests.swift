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
        XCTAssertTrue(app.staticTexts["player.time"].exists(within: 10))
        let close = app.buttons["player.close"]
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            waitUntil(3) {                                                  // turned
                let window = app.windows.firstMatch.frame
                return orientation == .portrait ? window.height > window.width : window.width > window.height
            }
            app.otherElements["player.surface"].firstMatch.tap()            // controls on (or off, then on)
            if !close.exists(within: 1) { app.otherElements["player.surface"].firstMatch.tap(); close.exists(within: 1) }
            shot(app, "player-\(orientation == .portrait ? "portrait" : "landscape")-chrome")
            if close.exists { XCTAssertTrue(app.windows.firstMatch.frame.contains(close.frame), "Close is off screen in \(orientation.rawValue)") }
            app.otherElements["player.surface"].firstMatch.tap()            // controls off: the picture alone
            close.gone(within: 2)
            shot(app, "player-\(orientation == .portrait ? "portrait" : "landscape")-clean")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.4)                                  // done fading, for the picture
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
