import XCTest

/// One search: describing something shows the library filtered to it —
/// through the search service when it's up (services/search in stub mode,
/// started by scripts/test.sh search), on the device when it isn't.
@MainActor
final class SearchTests: XCTestCase {
    func testDescribingSomethingFiltersTheLibraryThroughTheService() {
        let understood = search("funny films from the 80s", extra: ["-searchEndpoint", "http://localhost:8787/v1/interpret"])
        XCTAssertEqual(understood.value as? String, "service", "the service didn't answer (is `wrangler dev` running?)")
        XCTAssertTrue(understood.label.localizedCaseInsensitiveContains("comedy"), "got: \(understood.label)")
        XCTAssertTrue(understood.label.contains("1980s"), "got: \(understood.label)")
    }

    func testWithoutTheServiceTheDeviceReadsTheWords() {
        let understood = search("funny films from the 80s", extra: ["-searchEndpoint", "http://localhost:9/v1/interpret"])   // nothing there
        XCTAssertEqual(understood.value as? String, "device")
        XCTAssertTrue(understood.label.localizedCaseInsensitiveContains("comedy"), "got: \(understood.label)")
    }

    private func search(_ words: String, extra: [String]) -> XCUIElement {
        let app = XCUIApplication()
        // Typed for it (the tvOS search keyboard doesn't take synthesized typing).
        app.launchArguments = ["-mock", "-reset", "-route", "search", "-searchQuery", words] + extra
        app.launch()
        let understood = app.descendants(matching: .any).matching(identifier: "search.understood").firstMatch
        XCTAssertTrue(understood.exists(within: 6), "nothing understood from “\(words)”")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            XCUIRemote.shared.press(.right)                          // sidebar → the keyboard: the pill shows
            Thread.sleep(forTimeInterval: 1.5)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/search-understood.png"))
        }
        return understood
    }
}
