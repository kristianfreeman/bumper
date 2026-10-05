import XCTest

/// Queue: add from a page, and the plan leads Home.
@MainActor
final class QueueTests: XCTestCase {
    func testAddToQueueThenItLeadsHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-syncQueue", "-route", "item:movie-0001"]
        app.launch()
        let add = app.buttons["detail.queue"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no Add to Queue on the detail page")
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !add.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(add.hasFocus, "couldn't reach Add to Queue")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 0.5)
        remote.press(.menu)                                     // back to Home
        let queue = app.descendants(matching: .any)["collection.queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5), "Queue doesn't lead Home after adding")
        XCTAssertTrue(app.buttons["queue.play"].exists, "no Play Queue")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            Thread.sleep(forTimeInterval: 1)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/queue-home.png"))
            app.terminate()
            app.launchArguments = ["-mock", "-route", "queue"]          // no -reset: the plan persists
            app.launch()
            Thread.sleep(forTimeInterval: 2)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/queue-page.png"))
        }
    }
}
