import XCTest

/// Flicking through Home and a collection page on a real iPhone, for
/// scripts/phone-scroll-check.sh, which reads the app's frame timing
/// afterwards. Drives only; the script judges.
@MainActor
final class PhoneScrollTests: XCTestCase {
    func testFlickHome() { run(["-mock", "-reset"]) }
    func testFlickACollectionPage() { run(["-mock", "-reset", "-route", "grid:view-movies"]) }

    private func run(_ args: [String]) {
        let app = XCUIApplication()
        app.launchArguments = args + ["-metricsFile"]
        app.launch()
        Thread.sleep(forTimeInterval: 4)                     // content in, launch settled
        for _ in 0..<10 { app.swipeUp(velocity: .fast) }
        for _ in 0..<10 { app.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 2)                     // the last metrics write
    }
}
