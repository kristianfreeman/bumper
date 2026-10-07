import XCTest

/// The phone and the Apple TV app (in the tvOS simulator on the same Mac;
/// `scripts/companion-check.sh` starts it on a film's page).
@MainActor
final class CompanionTests: XCTestCase {
    /// One tap on the TV button connects, and the bar above the tabs says so;
    /// Play on the phone then starts on the TV, whose live status shows in
    /// the bar — with a play/pause that reaches the TV — and the bar opens
    /// Now Playing, which steers it too.
    func testConnectPlayOnTheTVAndSeeItLive() {
        let app = XCUIApplication()
        let item = ProcessInfo.processInfo.environment["ITEM"] ?? "media-0"
        let media = ProcessInfo.processInfo.environment["MEDIA"] ?? ""
        app.launchArguments = ["-mock", "-reset", "-mockMedia", media, "-route", "item:\(item)", "-uiTestNoAnimations"]
        app.launch()
        let castButton = app.buttons["cast.button"]
        XCTAssertTrue(castButton.waitForExistence(timeout: 20), "no TV button in the navigation bar")
        // Found the TV (the button connects straight away when there's one).
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, castButton.label != "Play on Apple TV" || !castButton.isHittable { Thread.sleep(forTimeInterval: 0.3) }
        Thread.sleep(forTimeInterval: 2)                     // the browser finds the TV
        castButton.tap()
        Thread.sleep(forTimeInterval: 0.5)
        shot("companion-after-tap")
        // More than one TV on the network (a real one running the app, too):
        // the button offers them — pick the simulator's.
        let simTV = app.buttons[ProcessInfo.processInfo.environment["TV_NAME"] ?? "Apple TV 4K (3rd generation)"]
        if simTV.waitForExistence(timeout: 1) { simTV.tap() }
        let bar = app.descendants(matching: .any)["cast.bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "no TV bar on connecting")
        XCTAssertTrue(bar.label.contains("Connected to"), "the bar says '\(bar.label)'")
        XCTAssertFalse(app.descendants(matching: .any)["cast.notice"].exists, "a notice repeats what the bar says")
        shot("companion-connected")

        let play = app.buttons["detail.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(play.label.contains(" on "), "Play doesn't say it plays on the TV: '\(play.label)'")
        play.tap()
        let expected = ProcessInfo.processInfo.environment["EXPECT_TITLE"] ?? "Long"
        let barDeadline = Date().addingTimeInterval(20)
        while Date() < barDeadline, !bar.label.contains(expected) { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(bar.label.contains(expected), "the TV bar shows '\(bar.label)', not what's playing on the TV (\(expected))")
        shot("companion-playing")

        let playPause = app.buttons["cast.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5), "no play/pause on the TV bar")
        playPause.tap()
        let pauseDeadline = Date().addingTimeInterval(8)
        while Date() < pauseDeadline, !bar.label.contains("Paused") { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(bar.label.contains("Paused"), "the TV didn't pause (bar: '\(bar.label)')")
        shot("companion-paused")

        bar.tap()
        let title = app.staticTexts["phone.playingTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the bar didn't open Now Playing")
        XCTAssertTrue(title.label.contains(expected), "Now Playing shows '\(title.label)'")
        let sheetPlay = app.buttons["phone.playPause"]
        XCTAssertEqual(sheetPlay.label, "Play", "Now Playing doesn't show the TV paused")
        sheetPlay.tap()
        let playDeadline = Date().addingTimeInterval(8)
        while Date() < playDeadline, sheetPlay.label != "Pause" { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(sheetPlay.label, "Pause", "Play in Now Playing didn't reach the TV")
        Thread.sleep(forTimeInterval: 1)
        shot("companion-now-playing")

        // Find Subtitles from the phone: the TV's server searches; the best
        // match goes on.
        app.buttons["phone.subtitles"].tap()
        let find = app.buttons["Find Subtitles…"]
        XCTAssertTrue(find.waitForExistence(timeout: 3), "no Find Subtitles in the subtitles menu")
        find.tap()
        let best = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Best match'")).firstMatch
        XCTAssertTrue(best.waitForExistence(timeout: 15), "no results from the TV")
        shot("companion-find-subtitles")
        best.tap()
        let subtitles = app.buttons["phone.subtitles"]
        let onDeadline = Date().addingTimeInterval(15)
        while Date() < onDeadline, (subtitles.value as? String ?? "") == "Off" || !subtitles.isHittable { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertNotEqual(subtitles.value as? String, "Off", "the found subtitle didn't go on")
        shot("companion-subtitle-on")
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
