import XCTest

/// A playlist: Play starts its first item, and what's next is its second
/// (it plays through in order) — not the show's next episode or the Queue.
@MainActor
final class PlaylistTests: XCTestCase {
    func testPlayGoesThroughThePlaylistInOrder() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockPlaylists", "-route", "item:playlist-marathon"]
        app.launch()
        let play = app.buttons["playlist.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "no playlist page")
        XCTAssertTrue(app.buttons["playlist.item.5"].waitForExistence(timeout: 5), "not all six items")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/playlist.png"))
        }
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !play.hasFocus { remote.press(.up); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(play.hasFocus, "Play isn't focused")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 10), "Play didn't play")
        // The info band's Up Next: the playlist's second item.
        Thread.sleep(forTimeInterval: 5)                              // the controls hide; Select brings them back
        remote.press(.select); Thread.sleep(forTimeInterval: 0.4)
        remote.press(.up); Thread.sleep(forTimeInterval: 0.5)
        for _ in 0..<3 { remote.press(.right) }
        remote.press(.select); Thread.sleep(forTimeInterval: 1)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/playlist-upnext.png"))
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'E2 · Chapter 2'")).firstMatch.exists, "Up Next isn't the playlist's second item")
    }
}
