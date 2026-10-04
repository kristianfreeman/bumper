import XCTest

/// A collection page: its sentence is made of pills, and asking in words changes it.
@MainActor
final class CollectionTests: XCTestCase {
    func testAskingInWordsFiltersTheCollection() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "grid:view-movies"]
        app.launch()
        let ask = app.buttons["filter.ask"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "collection page didn't open")
        let remote = XCUIRemote.shared
        for _ in 0..<6 where !ask.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        for _ in 0..<3 where !ask.hasFocus { remote.press(.up); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(ask.hasFocus, "couldn't reach Ask")
        remote.press(.select)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "no text field to ask in")
        remote.press(.select)                                   // open the keyboard
        Thread.sleep(forTimeInterval: 1)
        app.typeText("something funny I haven't seen")
        Thread.sleep(forTimeInterval: 0.5)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/collection-ask.png"))
        }
        let done = app.buttons.matching(NSPredicate(format: "label ==[c] 'done'")).firstMatch   // the keyboard's Done applies it
        for _ in 0..<5 where !done.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.3) }
        remote.press(.select)
        XCTAssertTrue(app.buttons["filter.watched"].waitForExistence(timeout: 3), "“haven't seen” didn't become an unwatched pill")
        XCTAssertTrue(app.buttons["filter.genre"].exists, "“funny” didn't become a genre pill")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            Thread.sleep(forTimeInterval: 1.5)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/collection-filtered.png"))
        }
    }
}
