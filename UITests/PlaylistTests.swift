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
        XCTAssertTrue(play.exists(within: 10), "no playlist page")
        XCTAssertTrue(app.buttons["playlist.item.5"].exists(within: 5), "not all six items")
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/playlist.png"))
        }
        let remote = XCUIRemote.shared
        remote.press(.up, in: app, atMost: 4) { play.hasFocus }
        XCTAssertTrue(play.hasFocus, "Play isn't focused")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["player.time"].exists(within: 10), "Play didn't play")
        // The info band's Up Next: the playlist's second item.
        let icons = app.buttons["control.subtitles"]
        icons.exists(within: 2)
        icons.gone(within: 6)                                        // the controls hide; Select brings them back
        remote.press(.select)
        icons.exists(within: 2)
        remote.press(.up)
        icons.waitForFocus()
        for _ in 0..<3 { remote.press(.right) }
        remote.press(.select)
        let upNext = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'E2 · Chapter 2'")).firstMatch
        upNext.exists(within: 3)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/playlist-upnext.png"))
        }
        XCTAssertTrue(upNext.exists, "Up Next isn't the playlist's second item")
    }
}
