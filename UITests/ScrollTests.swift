import XCTest

/// Moving down Home is the focus engine's own scrolling (the page doesn't
/// snap collections into place afterwards any more): each press moves focus
/// down, through the collections, and the focused card is always wholly on
/// screen.
@MainActor
final class ScrollTests: XCTestCase {
    func testDownMovesThroughCollectionsWithFocusOnScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].exists(within: 8))
        app.focusSettles()
        let remote = XCUIRemote.shared
        let screen = app.windows.firstMatch.frame
        var rows: [String] = []
        for press in 0..<6 {
            remote.press(.down, movingFocusIn: app)
            app.focusSettles(quiet: 0.2)                             // the page done scrolling to it
            // One look at the whole screen (each element's frame would be another).
            guard let screenful = try? app.snapshot() else { XCTFail("press \(press): no snapshot"); continue }
            let all = Self.flatten(screenful)
            guard let focused = all.first(where: \.hasFocus) else { XCTFail("press \(press): nothing focused"); continue }
            let frame = focused.frame
            XCTAssertTrue(screen.contains(frame.insetBy(dx: 2, dy: 2)), "press \(press): focused \(focused.identifier) is off screen at \(frame)")
            // The collection holding focus: the nearest title above the focused card.
            let headers = all.filter { $0.identifier.hasPrefix("collection.") }
            if let header = headers.filter({ $0.frame.maxY <= frame.minY + 1 }).max(by: { $0.frame.minY < $1.frame.minY }) {
                if rows.last != header.identifier { rows.append(header.identifier) }
            }
            XCTAssertNotEqual(focused.identifier, "", "press \(press): nothing focused")
        }
        print("SCROLL-DEBUG \(rows)")
        XCTAssertGreaterThanOrEqual(rows.count, 3, "didn't move through three collections: \(rows)")
        XCTAssertEqual(rows.count, Set(rows).count, "focus went back up to a collection it had left: \(rows)")
    }

    private static func flatten(_ element: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
        [element] + element.children.flatMap(flatten)
    }
}
