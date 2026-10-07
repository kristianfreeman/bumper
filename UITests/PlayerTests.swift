import XCTest

/// Player controls against real media (TestMedia/, served by the mock over
/// HTTP): the remote, focus, and what the real backends report. What the
/// player shows off the TV (the chapters list, a slow start's words, the
/// Untracked tag, Picture in Picture) is checked in-process:
/// AppFeaturesTests' Player.
@MainActor
final class PlayerTests: XCTestCase {
    static let media = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "TestMedia").path

    /// `clip` of TestMedia/ (5 s each), or of TestMedia/seek (two minutes).
    func launchPlaying(_ clip: Int, from folder: String = "", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-quickTimers", "-mockHTTP", "-mockMedia", Self.media + folder, "-autoplay", "media-\(clip)"] + extra
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
        // Menu steps back to the list (not out of the card), and in again.
        remote.press(.menu)
        XCTAssertTrue(find.waitForExistence(timeout: 2), "Menu from the results closed the card instead of going back to the list")
        for _ in 0..<8 where !find.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.25) }
        remote.press(.select)
        XCTAssertTrue(best.waitForExistence(timeout: 8), "no results the second time")
        XCTAssertTrue(waitForFocus(best, timeout: 2), "focus didn't land on the best match")
        XCTAssertTrue(best.label.contains("Best match"), "first result isn't marked: \(best.label)")
        remote.press(.select)
        XCTAssertTrue(waitFor(status, label: { $0 != "off" }, timeout: 5), "the found subtitle didn't come on (VLCKit reports '\(status.label)')")
    }

    /// Playback (Background and the sleep timer, only here): the sleep
    /// timer sets from its card, and the pill then shows the time left.
    func testSleepTimerFromPlayback() {
        let app = launchPlaying(6)
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 8), "it didn't play")
        let remote = XCUIRemote.shared
        remote.press(.playPause)
        remote.press(.up)
        let playback = app.buttons["control.playback"]
        XCTAssertTrue(playback.waitForExistence(timeout: 2), "no Playback in the player")
        for _ in 0..<4 where !playback.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(playback.hasFocus, "couldn't reach Playback")
        remote.press(.select)
        let fifteen = app.buttons["option.sleep-15"]
        XCTAssertTrue(fifteen.waitForExistence(timeout: 2), "no sleep options")
        XCTAssertTrue(app.buttons["option.background"].exists, "no Untracked switch")
        for _ in 0..<4 where !fifteen.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.3) }
        remote.press(.select)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !(playback.value as? String ?? "").contains("m") { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertTrue(["Stops in 15m", "Stops in 14m"].contains(playback.value as? String ?? ""), "the pill doesn't show the time left (\(playback.value ?? "nil"))")
    }

    /// Select with the controls down brings them up and the video plays on;
    /// on the icons, Play/Pause still pauses and plays, and Left from the
    /// first goes nowhere.
    func testSelectShowsTheControlsAndPlayPauseWorksFromTheIcons() {
        let app = launchPlaying(2, from: "/seek", extra: ["-startAt", "40"])     // past the intro; too long to end mid-test
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 8), "it didn't play")
        Thread.sleep(forTimeInterval: 1.2)                            // the controls hide (in 0.8 s: -quickTimers)
        let remote = XCUIRemote.shared
        let subtitles = app.buttons["control.subtitles"]
        XCTAssertFalse(subtitles.exists, "the controls didn't hide")
        remote.press(.select)
        XCTAssertTrue(subtitles.exists(within: 2), "Select didn't bring the controls up")      // (they go again in 0.8 s)
        XCTAssertTrue(app.descendants(matching: .any)["transport.playing"].exists, "Select paused instead of only showing the controls")
        remote.press(.up)
        XCTAssertTrue(waitForFocus(subtitles, timeout: 2), "Up didn't reach the icons")
        remote.press(.playPause)                                     // paused, the controls stay up
        XCTAssertTrue(app.descendants(matching: .any)["transport.paused"].exists(within: 2), "Play/Pause on the icons didn't pause")
        remote.press(.left)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(subtitles.hasFocus, "Left from the first icon left the icons")
        remote.press(.playPause)
        XCTAssertTrue(app.descendants(matching: .any)["transport.playing"].exists(within: 2), "Play/Pause on the icons didn't resume")
    }

    /// Left alone on the icons while it plays, the controls go: 8 s, 1.6 at
    /// -quickTimers' pace (from the video, 0.8).
    func testIdleControlsHideFromTheIcons() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-quickTimers", "-mockHTTP", "-mockMedia", Self.media, "-autoplay", "series-001-s1-e2", "-startAt", "300"]   // 10 minutes, past its intro
        app.launch()
        XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 8), "it didn't play")
        let remote = XCUIRemote.shared
        let subtitles = app.buttons["control.subtitles"]
        Thread.sleep(forTimeInterval: 1.2)                            // up at the start; gone (Select now shows, not pauses)
        remote.press(.select)
        XCTAssertTrue(subtitles.exists(within: 2), "Select didn't bring the controls up")      // (they go again in 0.8 s)
        remote.press(.up)
        XCTAssertTrue(subtitles.waitForFocus(), "Up didn't reach the icons")
        let onIcons = Date()
        XCTAssertTrue(subtitles.gone(within: 4), "the controls stayed up, left alone")
        // From when focus was seen there (a little after it landed): the
        // video's 0.8 s would be well under a second.
        let stayed = Date().timeIntervalSince(onIcons)
        print("IDLE-HIDE stayed \(stayed) s")
        XCTAssertGreaterThan(stayed, 1.2, "the controls went too soon (after \(stayed) s)")
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
            app.launchArguments = ["-mock", "-quickTimers", "-mockHTTP", "-mockMedia", seekMedia, "-autoplay", "media-\(clip)"]
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

    /// Chapters (the mock's: 0:30 "The Harbour at Night", 1:00 "Chapter 03",
    /// 1:30 "Landfall"): marked on the timeline; the card from the icon row
    /// starts on the one playing, and choosing another goes there.
    func testChaptersCardGoesToAChapter() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-quickTimers", "-mockHTTP", "-mockMedia", Self.media + "/seek", "-autoplay", "media-2"]   // 2 min MP4 → AVPlayer
        app.launch()
        let time = app.staticTexts["player.time"]
        XCTAssertTrue(waitFor(time, label: { (Int($0) ?? 0) > 500 }, timeout: 8), "it didn't play")
        let remote = XCUIRemote.shared
        remote.press(.playPause)                                     // before the mock's intro (0:05) offers Skip
        XCTAssertTrue(app.descendants(matching: .any)["transport.paused"].waitForExistence(timeout: 2), "didn't pause")
        XCTAssertTrue(app.descendants(matching: .any)["timeline.chapters"].waitForExistence(timeout: 3), "no chapter marks on the timeline")
        remote.press(.up)
        let pill = app.buttons["control.chapters"]
        XCTAssertTrue(pill.waitForExistence(timeout: 3), "no Chapters in the player")
        for _ in 0..<6 where !pill.hasFocus { remote.press(.right); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(pill.hasFocus, "couldn't reach Chapters")
        remote.press(.select)
        let first = app.buttons["option.chapter-0"], third = app.buttons["option.chapter-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 2), "the Chapters card didn't open")
        XCTAssertTrue(waitForFocus(first, timeout: 2), "focus should start on the chapter playing")
        XCTAssertEqual(first.value as? String, "selected", "the chapter playing isn't marked")
        XCTAssertTrue(third.label.contains("Chapter 3"), "an unnamed chapter should read \"Chapter 3\" (\(third.label))")
        for _ in 0..<4 where !third.hasFocus { remote.press(.down); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(third.hasFocus, "couldn't reach the third chapter")
        remote.press(.select)
        XCTAssertTrue(waitFor(time, label: { abs((Int($0) ?? 0) - 60_000) < 1_500 }, timeout: 4), "didn't go to 1:00 (at \(time.label) ms)")
        XCTAssertTrue(waitForFocus(pill, timeout: 2), "focus didn't return to the Chapters pill")
    }

    /// Scrubbing names the chapter under the head, under the thumbnail.
    func testScrubbingNamesTheChapter() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-quickTimers", "-mockHTTP", "-mockMedia", Self.media + "/seek", "-autoplay", "media-2"]
        app.launch()
        let time = app.staticTexts["player.time"]
        XCTAssertTrue(waitFor(time, label: { (Int($0) ?? 0) > 500 }, timeout: 8), "it didn't play")
        let remote = XCUIRemote.shared
        remote.press(.playPause)
        XCTAssertTrue(app.descendants(matching: .any)["transport.paused"].waitForExistence(timeout: 2), "didn't pause")
        let chapter = app.staticTexts["scrub.chapter"]
        for _ in 0..<3 { remote.press(.right) }                       // the head at ~0:31
        XCTAssertTrue(waitFor(chapter, label: { $0 == "The Harbour at Night" }, timeout: 2), "scrub shows \(chapter.exists ? chapter.label : "no chapter")")
        for _ in 0..<6 { remote.press(.right) }                       // ~1:31
        XCTAssertTrue(waitFor(chapter, label: { $0 == "Landfall" }, timeout: 2), "scrub shows \(chapter.exists ? chapter.label : "no chapter")")
        remote.press(.menu)                                          // cancel the scrub
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
