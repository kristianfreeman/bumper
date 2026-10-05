import XCTest

/// Moving into a collection brings the whole of it into place: each one's
/// title ends up at the same height on screen, not wherever the minimal
/// scroll left it.
@MainActor
final class ScrollTests: XCTestCase {
    func testCollectionsSettleInTheSamePlace() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.5)
        let remote = XCUIRemote.shared
        var titles: [(String, CGFloat)] = []
        for _ in 0..<3 {
            // Two rows per collection: two Downs reach the next one.
            remote.press(.down); Thread.sleep(forTimeInterval: 0.5)
            remote.press(.down); Thread.sleep(forTimeInterval: 1.8)   // the snap waits for the focus scroll to finish
            let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
            let headers = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'collection.'")).allElementsBoundByIndex
            // The collection holding focus: the nearest title above the focused card.
            guard let header = headers.filter({ $0.frame.maxY <= focused.frame.minY + 1 }).max(by: { $0.frame.minY < $1.frame.minY }) else {
                XCTFail("no collection title above \(focused.identifier)"); return
            }
            titles.append((header.identifier, header.frame.minY))
        }
        print("SCROLL-DEBUG \(titles)")
        XCTAssertEqual(Set(titles.map(\.0)).count, 3, "didn't move through three collections: \(titles)")
        let ys = titles.map(\.1)
        XCTAssertLessThan((ys.max() ?? 0) - (ys.min() ?? 0), 12, "titles settled at different heights: \(titles)")
    }
}
