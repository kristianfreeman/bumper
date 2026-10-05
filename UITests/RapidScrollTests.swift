import XCTest

/// Fast scrolling, for the real Apple TV (scripts/device-scroll-check.sh reads
/// the app's focus trace afterwards to find pull-backs: focus moving up while
/// only Down was pressed). Drives only; the script judges.
@MainActor
final class RapidScrollTests: XCTestCase {
    func testRapidDownOnHome() { run(["-mock", "-reset"], wait: "collection.resume") }
    func testRapidDownOnACollectionPage() { run(["-mock", "-reset", "-route", "grid:view-movies"], wait: "filter.add") }

    private func run(_ args: [String], wait identifier: String) {
        let app = XCUIApplication()
        // TEST_RUNNER_EXTRA_ARGS="-mockLatency 700": a slow server.
        app.launchArguments = args + ["-metricsFile"] + (ProcessInfo.processInfo.environment["EXTRA_ARGS"]?.split(separator: " ").map(String.init) ?? [])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        let remote = XCUIRemote.shared
        for _ in 0..<24 { remote.press(.down) }          // as fast as the remote API goes
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<24 { remote.press(.up) }
        Thread.sleep(forTimeInterval: 2)
    }
}
