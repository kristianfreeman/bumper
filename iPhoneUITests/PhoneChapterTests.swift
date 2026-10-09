import XCTest

/// Chapters on the iPhone after a turn, on the 20-minute clip (the mock's
/// chapters: 5:00 "The Harbour at Night", 10:00 "Chapter 03", 15:00
/// "Landfall"): on its side, a menu beside the timeline. (Upright, Up
/// Next is under the picture, not chapters.)
@MainActor
final class PhoneChapterTests: XCTestCase {
    static let media = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "TestMedia/long").path

    func testChaptersMenuOnItsSide() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockPort", "0", "-reset", "-mockMedia", Self.media, "-autoplay", "media-0"]
        app.launch()
        let time = app.staticTexts["player.time"]
        XCTAssertTrue(waitFor(time, timeout: 10) { (Int($0) ?? 0) > 500 }, "it didn't play")
        XCTAssertTrue(app.buttons["upnext.add"].exists(within: 5), "no Up Next under the picture")

        // Paused, the controls stay up through the turn (playing, they hid
        // 4 s after the last touch — sometimes mid-test).
        let playPause = app.buttons["player.playPause"]
        playPause.tap()
        XCTAssertTrue(waitFor(playPause, timeout: 2) { $0 == "Play" }, "didn't pause")
        XCUIDevice.shared.orientation = .landscapeLeft
        let menu = app.buttons["control.chapters"]
        if !menu.exists(within: 3) { app.otherElements["player.surface"].firstMatch.tap() }
        XCTAssertTrue(menu.exists(within: 3), "no Chapters beside the timeline")
        menu.tap()
        let landfall = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Landfall'")).firstMatch
        XCTAssertTrue(landfall.exists(within: 2), "the Chapters menu didn't open")
        landfall.tap()
        app.buttons["player.playPause"].tap()
        XCTAssertTrue(waitFor(time, timeout: 5) { abs((Int($0) ?? 0) - 900_000) < 3_000 }, "didn't go to 15:00 (at \(time.label) ms)")
        XCUIDevice.shared.orientation = .portrait
    }

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval, _ matches: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, matches(element.label) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}
