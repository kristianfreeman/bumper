import XCTest

/// Pages open, and come back, on the iPhone.
@MainActor
final class PhoneNavigationTests: XCTestCase {
    /// Every View all on Home opens its page, and Back returns (one crashed).
    func testViewAllOpensAndComesBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].exists(within: 10))
        for i in 0..<3 {
            let tiles = app.buttons.matching(identifier: "collection.viewAll")
            var tries = 0
            while tiles.count <= i || !tiles.element(boundBy: i).isHittable, tries < 12 { app.swipeUp(); tries += 1 }
            guard tiles.count > i else { break }
            tiles.element(boundBy: i).tap()
            let back = app.navigationBars.buttons["BackButton"]    // (the bar also holds the TV, sleep and profile buttons)
            back.settles()                                         // the page done pushing in
            XCTAssertEqual(app.state, .runningForeground, "View all #\(i) crashed the app")
            XCTAssertTrue(back.exists, "View all #\(i): no way back")
            back.tap()
            back.gone(within: 3)
        }
    }

    /// A quick double tap on View all (the page opening twice crashed SwiftUI's navigation).
    func testDoubleTapOnViewAll() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].exists(within: 10))
        let tiles = app.buttons.matching(identifier: "collection.viewAll")
        var tries = 0
        while tiles.count < 2 || !tiles.element(boundBy: 1).isHittable, tries < 12 { app.swipeUp(); tries += 1 }
        for i in 0..<min(2, tiles.count) {
            tiles.element(boundBy: i).doubleTap()
            let back = app.navigationBars.buttons["BackButton"]
            back.settles(quiet: 0.5)                                 // a second push, if there was one, landed too
            XCTAssertEqual(app.state, .runningForeground, "double tap on View all #\(i) crashed the app")
            for _ in 0..<4 where back.exists { back.tap(); if !back.gone(within: 1) { back.settles() } }
        }
    }
}
