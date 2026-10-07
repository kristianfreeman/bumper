import XCTest

/// A show's page: the season bar follows focus along the episode row.
/// Picking a season, and an episode opening in its season, are checked
/// in-process: AppFeaturesTests' Seasons.
@MainActor
final class SeasonTests: XCTestCase {
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testTheSeasonBarFollowsTheEpisodes() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-route", "item:series-003"]           // four seasons; ten episodes in the first
        app.launch()
        let one = app.buttons["season.1"], two = app.buttons["season.2"]
        XCTAssertTrue(one.waitForExistence(timeout: 10), "no season bar")
        let remote = XCUIRemote.shared
        // Down to the episodes (past the bar), then along into season 2.
        let focusedEpisode = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label CONTAINS 'Chapter'")).firstMatch
        for _ in 0..<4 where !focusedEpisode.exists { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(focusedEpisode.exists, "couldn't reach the episodes")
        for _ in 0..<14 where !two.isSelected { remote.press(.right); Thread.sleep(forTimeInterval: 0.35) }
        shot("season-following")
        XCTAssertTrue(two.isSelected, "moving into season 2's episodes didn't move the bar")
    }
}
