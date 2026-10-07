import XCTest

/// Queue: reaching Add to Queue with the remote. Adding, and the plan then
/// leading Home, is checked in-process: AppFeaturesTests' Queue.
@MainActor
final class QueueTests: XCTestCase {
    func testAddToQueueWithTheRemote() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-syncQueue", "-route", "item:movie-0001"]
        app.launch()
        let add = app.buttons["detail.queue"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no Add to Queue on the detail page")
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !add.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(add.hasFocus, "couldn't reach Add to Queue")
        remote.press(.select)
        let added = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "detail.queue", "In Queue")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 3), "Select didn't add it (\(add.label))")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            remote.press(.menu)                                 // back to Home, led by the Queue
            XCTAssertTrue(app.descendants(matching: .any)["collection.queue"].waitForExistence(timeout: 5))
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
