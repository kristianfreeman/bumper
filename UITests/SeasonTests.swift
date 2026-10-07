import XCTest

/// A show's page: the season bar follows the episode row, picking a season
/// jumps to it, and an episode opens inside its show, in its season.
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
        let one = app.buttons["season.1"], two = app.buttons["season.2"], four = app.buttons["season.4"]
        XCTAssertTrue(one.waitForExistence(timeout: 10), "no season bar")
        let remote = XCUIRemote.shared
        // Down to the episodes (past the bar), then along into season 2.
        let focusedEpisode = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label CONTAINS 'Chapter'")).firstMatch
        for _ in 0..<4 where !focusedEpisode.exists { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(focusedEpisode.exists, "couldn't reach the episodes")
        for _ in 0..<14 where !two.isSelected { remote.press(.right); Thread.sleep(forTimeInterval: 0.35) }
        shot("season-following")
        XCTAssertTrue(two.isSelected, "moving into season 2's episodes didn't move the bar")
        // Up to the bar, over to season 4, select: the row jumps there.
        for _ in 0..<3 where !(app.buttons.allElementsBoundByIndex.contains { $0.identifier.hasPrefix("season.") && $0.hasFocus }) {
            remote.press(.up); Thread.sleep(forTimeInterval: 0.4)
        }
        for _ in 0..<4 where !four.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.35) }
        XCTAssertTrue(four.hasFocus, "couldn't reach Season 4")
        remote.press(.select); Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(four.isSelected, "picking Season 4 didn't select it")
        remote.press(.down); Thread.sleep(forTimeInterval: 0.6)
        shot("season-jumped")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'S4 · E'")).firstMatch.exists, "the row didn't jump to Season 4")
    }

    func testAnEpisodeOpensInItsSeason() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-route", "item:series-003-s2-e4"]
        app.launch()
        let two = app.buttons["season.2"]
        XCTAssertTrue(two.waitForExistence(timeout: 10), "the episode didn't open in its show")
        XCTAssertTrue(two.isSelected, "not in its season")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'S2 · E4'")).firstMatch.exists, "the header isn't the episode")
        shot("season-episode-context")
    }
}
