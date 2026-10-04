import XCTest

/// Tonight: add from a page, and the plan leads Home.
@MainActor
final class TonightTests: XCTestCase {
    func testAddToTonightThenItLeadsHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        let add = app.buttons["detail.tonight"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no Add to Tonight on the detail page")
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !add.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(add.hasFocus, "couldn't reach Add to Tonight")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.menu)                                     // back to Home
        let tonight = app.descendants(matching: .any)["collection.tonight"]
        XCTAssertTrue(tonight.waitForExistence(timeout: 5), "Tonight doesn't lead Home after adding")
        XCTAssertTrue(app.buttons["tonight.play"].exists, "no Play Tonight")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            Thread.sleep(forTimeInterval: 1)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/tonight-home.png"))
            app.terminate()
            app.launchArguments = ["-mock", "-route", "tonight"]          // no -reset: the plan persists
            app.launch()
            Thread.sleep(forTimeInterval: 2)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/tonight-page.png"))
        }
    }
}
