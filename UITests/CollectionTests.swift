import XCTest

/// A collection page: its sentence is made of pills, and asking in words changes it.
@MainActor
final class CollectionTests: XCTestCase {
    func testAskingInWordsFiltersTheCollection() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "grid:view-movies"]
        app.launch()
        let ask = app.buttons["filter.ask"]
        XCTAssertTrue(ask.exists(within: 5), "collection page didn't open")
        app.focusSettles()
        let remote = XCUIRemote.shared
        remote.press(.right, in: app, atMost: 6) { ask.hasFocus }
        remote.press(.up, in: app, atMost: 3) { ask.hasFocus }
        XCTAssertTrue(ask.hasFocus, "couldn't reach Ask")
        remote.press(.select)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.exists(within: 3), "no text field to ask in")
        remote.press(.select)                                   // open the keyboard
        Thread.sleep(forTimeInterval: 1)
        app.typeText("something funny I haven't seen")
        Thread.sleep(forTimeInterval: 0.5)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/collection-ask.png"))
        }
        let done = app.buttons.matching(NSPredicate(format: "label ==[c] 'done'")).firstMatch   // the keyboard's Done applies it
        remote.press(.down, in: app, atMost: 5) { done.hasFocus }
        remote.press(.select)
        XCTAssertTrue(app.buttons["filter.watched"].exists(within: 3), "“haven't seen” didn't become an unwatched pill")
        XCTAssertTrue(app.buttons["filter.genre"].exists, "“funny” didn't become a genre pill")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            Thread.sleep(forTimeInterval: 1.5)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/collection-filtered.png"))
        }
    }

    /// Filter → When added → This week: a pill appears, with no menus, and
    /// focus comes back to it. Opening the row leaves focus on Filter.
    func testAddingAFilterInline() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "grid:view-movies"]
        app.launch()
        let add = app.buttons["filter.add"]
        XCTAssertTrue(add.exists(within: 5))
        app.focusSettles()
        let remote = XCUIRemote.shared
        remote.press(.up, in: app, atMost: 4) { add.hasFocus }
        remote.press(.left, in: app, atMost: 4) { add.hasFocus }
        XCTAssertTrue(add.hasFocus, "couldn't reach Filter")
        remote.press(.select)
        let whenAdded = app.buttons["filter.option.add.added"]
        XCTAssertTrue(whenAdded.exists(within: 2), "Filter didn't open its row")
        XCTAssertTrue(add.hasFocus, "opening the row took focus off Filter")
        remote.press(.down, movingFocusIn: app)                         // into the row
        remote.press(.left, in: app, atMost: 6) { whenAdded.hasFocus }
        remote.press(.select)
        let week = app.buttons["filter.option.added.week"]
        XCTAssertTrue(week.exists(within: 2), "no When added choices")
        remote.press(.left, in: app, atMost: 6) { week.hasFocus }
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/filter-week.png"))
        }
        remote.press(.select)
        let pill = app.buttons["filter.added"]
        XCTAssertTrue(pill.exists(within: 2), "no 'added this week' pill")
        XCTAssertTrue(pill.waitForFocus(), "focus didn't come back to the new pill")
        XCTAssertFalse(week.exists, "the choice row didn't close")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            remote.press(.select)                                       // reopen it, for the screenshot
            Thread.sleep(forTimeInterval: 0.8)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/filter-row.png"))
        }
    }
}
