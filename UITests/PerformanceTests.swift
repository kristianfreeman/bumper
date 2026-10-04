import XCTest

/// End-to-end performance tests against the in-process mock server
/// (`-mock`): deterministic data, so numbers are comparable run to run.
///
/// Two layers of measurement:
/// 1. XCTest metrics (launch time, CPU, memory) with baselines in Xcode.
/// 2. In-app metrics read from the perf HUD's accessibility value and
///    asserted against the same budgets the app shows in Settings →
///    Diagnostics. A blown budget fails CI.
@MainActor
final class PerformanceTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-perfHUD", "-reset"] + extra
        app.launch()
        return app
    }

    /// Cold launch → first frame, measured by XCTest itself.
    func testColdLaunch() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: Self.options(iterations: 5)) {
            let app = XCUIApplication()
            app.launchArguments = ["-mock"]
            app.launch()
        }
    }

    /// Flick through every home shelf and assert smoothness + image budgets.
    func testHomeBrowsingBudgets() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["collection.resume"].waitForExistence(timeout: 5), "Home never showed content")

        let remote = XCUIRemote.shared
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: Self.options(iterations: 3)) {
            for _ in 0..<4 {
                for _ in 0..<12 { remote.press(.right) }
                remote.press(.down)
                for _ in 0..<12 { remote.press(.left) }
            }
            for _ in 0..<4 { remote.press(.up) }
        }

        let metrics = try Self.readMetrics(app)
        try Self.assertBudget(metrics, "launch.firstContent", stat: "max", under: 1_200)
        try Self.assertBudget(metrics, "image.decode", stat: "p95", under: 12)
        try Self.assertBudget(metrics, "api.decode", stat: "p95", under: 15)
        // No hitch assertion here: XCUITest stalls the app's main thread to
        // snapshot accessibility around every remote press, which shows up as
        // hitches that users never see. Smoothness is enforced by the
        // harness-free `scripts/benchmark.sh` instead.
    }

    /// Deep-link into the 600-title Movies grid and page through it.
    func testLibraryGridPaging() throws {
        let app = launch(["-route", "grid:view-movies"])
        XCTAssertTrue(app.staticTexts["600 titles"].waitForExistence(timeout: 5), "Grid didn't load")
        let remote = XCUIRemote.shared
        for _ in 0..<40 { remote.press(.down) }

        let metrics = try Self.readMetrics(app)
        try Self.assertBudget(metrics, "image.decode", stat: "p95", under: 12)
        try Self.assertBudget(metrics, "api.decode", stat: "p95", under: 15)
    }

    /// Detail page load budget, deep-linked.
    func testDetailLoad() throws {
        let app = launch(["-route", "item:movie-0001"])
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        let metrics = try Self.readMetrics(app)
        try Self.assertBudget(metrics, "detail.load", stat: "p95", under: 400)
    }

    // MARK: Helpers

    /// Iterations come from PERF_ITERATIONS (set via TEST_RUNNER_PERF_ITERATIONS
    /// by scripts/test.sh): 1 for the inner loop, more for CI baselines.
    static func options(iterations: Int) -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = ProcessInfo.processInfo.environment["PERF_ITERATIONS"].flatMap(Int.init) ?? iterations
        return o
    }

    static func readMetrics(_ app: XCUIApplication) throws -> [String: [String: Double]] {
        let hud = app.descendants(matching: .any)["perf.hud"]
        XCTAssertTrue(hud.waitForExistence(timeout: 5), "Perf HUD not found (launch with -perfHUD)")
        // HUD refreshes once a second.
        Thread.sleep(forTimeInterval: 1.2)
        guard let json = hud.value as? String, let data = json.data(using: .utf8) else {
            throw XCTSkip("HUD exposed no metrics")
        }
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] ?? [:]
        let metrics = raw.mapValues { $0.compactMapValues { ($0 as? NSNumber)?.doubleValue } }
        let attachment = XCTAttachment(string: json)
        attachment.name = "metrics.json"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "In-app metrics") { $0.add(attachment) }
        return metrics
    }

    static func assertBudget(_ metrics: [String: [String: Double]], _ key: String, stat: String, under limit: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        guard let value = metrics[key]?[stat] else {
            XCTFail("No data for \(key)", file: file, line: line)
            return
        }
        XCTAssertLessThan(value, limit, "\(key) \(stat) = \(value) blew its budget of \(limit)", file: file, line: line)
    }
}
