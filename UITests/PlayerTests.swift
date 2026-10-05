import XCTest

/// Player controls against real media (TestMedia/, served by the mock over HTTP).
@MainActor
final class PlayerTests: XCTestCase {
    static let media = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "TestMedia").path

    func launchPlaying(_ clip: Int, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockMedia", Self.media, "-autoplay", "media-\(clip)"] + extra
        app.launch()
        return app
    }

    /// MKV + ASS plays on VLCKit with subtitles on by default; the icon
    /// row above the timeline opens the subtitle menu with the remote, and
    /// VLCKit itself reports each change.
    func testSubtitlesOnByDefaultAndSelectableWithRemote() {
        let app = launchPlaying(1)   // MKV · H.264 + DTS + ASS → VLCKit
        let status = app.staticTexts["player.subtitles"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(status, label: { $0 != "off" }, timeout: 4), "No subtitle track on by default (VLCKit reports '\(status.label)')")

        let remote = XCUIRemote.shared
        remote.press(.playPause)                     // keep the 5 s clip from ending mid-test
        remote.press(.up)
        let icon = app.buttons["control.subtitles"]
        XCTAssertTrue(icon.waitForExistence(timeout: 2) && waitForFocus(icon), "Up should focus the Subtitles icon")
        remote.press(.select)
        let off = app.buttons["option.sub-off"]
        let firstTrack = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'option.sub-' AND identifier != 'option.sub-off'")).firstMatch
        XCTAssertTrue(firstTrack.waitForExistence(timeout: 2), "Subtitle menu didn't open")
        XCTAssertTrue(waitForFocus(firstTrack), "Focus should start on the selected subtitle track")

        remote.press(.up)
        XCTAssertTrue(waitForFocus(off), "Up should move to 'Off'")
        remote.press(.select)
        XCTAssertTrue(waitFor(status, label: { $0 == "off" }, timeout: 2), "VLCKit still shows a subtitle after choosing Off")
        XCTAssertTrue(waitForFocus(icon, timeout: 2), "focus didn't return to the Subtitles pill")
        remote.press(.select)                        // menu closed, focus back on the icon → reopen
        XCTAssertTrue(off.waitForExistence(timeout: 2) && waitForFocus(off, timeout: 2.5), "Reopened menu should focus the chosen option")
        remote.press(.down)
        remote.press(.select)
        XCTAssertTrue(waitFor(status, label: { $0 != "off" }, timeout: 2), "Subtitle didn't come back")
    }

    /// Subtitles → Find Subtitles: the server's subtitle search, best fit
    /// first (the hash match), and picking it puts it on at once.
    func testFindSubtitlesUsesTheBestMatch() throws {
        // The mock server's subtitle search; no ranking service (the device judges).
        let app = launchPlaying(1, extra: ["-searchEndpoint", "http://localhost:9/v1/interpret"])
        let status = app.staticTexts["player.subtitles"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let remote = XCUIRemote.shared
        remote.press(.playPause)
        remote.press(.up)
        let icon = app.buttons["control.subtitles"]
        XCTAssertTrue(icon.waitForExistence(timeout: 2) && waitForFocus(icon))
        remote.press(.select)
        let off = app.buttons["option.sub-off"]
        XCTAssertTrue(off.waitForExistence(timeout: 2))
        for _ in 0..<4 where !off.hasFocus { remote.press(.up) }
        remote.press(.select)                                        // Off first, so a change is visible
        XCTAssertTrue(waitFor(status, label: { $0 == "off" }, timeout: 2))
        XCTAssertTrue(waitForFocus(icon, timeout: 2))
        remote.press(.select)
        let find = app.buttons["option.sub-find"]
        XCTAssertTrue(find.waitForExistence(timeout: 2), "no Find Subtitles")
        for _ in 0..<8 where !find.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(find.hasFocus, "couldn't reach Find Subtitles")
        remote.press(.select)
        let best = app.buttons["option.found-os-1001"]
        XCTAssertTrue(best.waitForExistence(timeout: 8), "no results")
        XCTAssertTrue(waitForFocus(best, timeout: 2), "focus didn't land on the best match")
        XCTAssertTrue(best.label.contains("Best match"), "first result isn't marked: \(best.label)")
        remote.press(.select)
        XCTAssertTrue(waitFor(status, label: { $0 != "off" }, timeout: 5), "the found subtitle didn't come on (VLCKit reports '\(status.label)')")
    }

    /// Background Noise from a page: it plays, and says it isn't marking anything watched.
    func testBackgroundNoiseSaysItIsNotMarkingWatched() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockMedia", Self.media, "-route", "item:media-0"]
        app.launch()
        let background = app.buttons["detail.background"]
        XCTAssertTrue(background.waitForExistence(timeout: 8), "no Background Noise on the page")
        let remote = XCUIRemote.shared
        for _ in 0..<6 where !background.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(background.hasFocus, "couldn't reach Background Noise")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 8), "it didn't play")
        remote.press(.playPause)                                    // chrome up
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'not marking watched'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3), "the player doesn't say it's in the background")
    }

    /// One press of Play/Pause pauses — and stays paused. (It could arrive
    /// twice, via SwiftUI and the Now Playing command, and cancel itself.)
    func testPlayPauseButtonPausesOnce() {
        let app = launchPlaying(6)   // H.264 + AAC MP4 → AVPlayer, Now Playing active
        Thread.sleep(forTimeInterval: 1.5)           // launched and playing (the clip is 5 s)
        XCUIRemote.shared.press(.playPause)
        let pausedIcon = app.descendants(matching: .any)["transport.paused"]
        XCTAssertTrue(pausedIcon.waitForExistence(timeout: 1), "Play/Pause didn't pause")
        Thread.sleep(forTimeInterval: 0.6)           // a double-delivered press would resume by now
        XCTAssertTrue(pausedIcon.exists, "Pause undid itself")
    }

    /// Pause, click right three times (the head moves +30 s), Select: playback
    /// resumes exactly at the head — on both backends. (Swipes are covered by
    /// TransportModelTests; XCUIRemote can't swipe.)
    func testScrubWithClicksResumesExactlyAtTheHead() {
        let seekMedia = Self.media + "/seek"
        for clip in [0, 2] {                                  // MKV → VLCKit, MP4 → AVPlayer
            let app = XCUIApplication()
            app.launchArguments = ["-mock", "-mockHTTP", "-mockMedia", seekMedia, "-autoplay", "media-\(clip)"]
            app.launch()
            let time = app.staticTexts["player.time"], head = app.staticTexts["player.head"]
            XCTAssertTrue(waitFor(time, label: { (Int($0) ?? 0) > 1000 }, timeout: 8), "clip \(clip) didn't start")
            let remote = XCUIRemote.shared
            remote.press(.playPause)
            XCTAssertTrue(app.descendants(matching: .any)["transport.paused"].waitForExistence(timeout: 2), "clip \(clip): didn't pause")
            let paused = Int(time.label) ?? 0
            for _ in 0..<3 { remote.press(.right) }
            XCTAssertTrue(waitFor(head, label: { Int($0) == paused + 30_000 }, timeout: 2), "clip \(clip): head \(head.label), expected \(paused + 30_000)")
            XCTAssertTrue(app.descendants(matching: .any)["scrub.preview"].exists, "clip \(clip): no scrub preview")
            let target = Int(head.label) ?? 0
            remote.press(.select)
            XCTAssertTrue(waitFor(app.descendants(matching: .any)["transport.playing"], label: { _ in true }, timeout: 5), "clip \(clip): didn't play")
            Thread.sleep(forTimeInterval: 1)
            let now = Int(time.label) ?? 0
            XCTAssertTrue(now >= target - 600 && now <= target + 2_500, "clip \(clip): resumed at \(now) ms, head was \(target) ms")
            app.terminate()
        }
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 1) -> Bool {
        waitFor(element, label: { _ in element.hasFocus }, timeout: timeout)
    }

    private func waitFor(_ element: XCUIElement, label matches: @escaping (String) -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, matches(element.label) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}
