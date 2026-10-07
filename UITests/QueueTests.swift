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
        XCTAssertTrue(add.exists(within: 5), "no Add to Queue on the detail page")
        let remote = XCUIRemote.shared
        remote.press(.right, in: app, atMost: 4) { add.hasFocus }
        XCTAssertTrue(add.hasFocus, "couldn't reach Add to Queue")
        remote.press(.select)
        let added = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "detail.queue", "In Queue")).firstMatch
        XCTAssertTrue(added.exists(within: 3), "Select didn't add it (\(add.label))")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            remote.press(.menu)                                 // back to Home, led by the Queue
            XCTAssertTrue(app.descendants(matching: .any)["collection.queue"].exists(within: 5))
            app.focusSettles()
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/queue-home.png"))
            app.terminate()
            app.launchArguments = ["-mock", "-route", "queue"]          // no -reset: the plan persists
            app.launch()
            app.staticTexts["Queue"].exists(within: 5)
            app.focusSettles()
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/queue-page.png"))
        }
    }
}
