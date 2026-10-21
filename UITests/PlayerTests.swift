import XCTest

// The player against real media (TestMedia/, served by the mock over HTTP):
// the remote, focus, and what the real backends report. What the player
// shows off the TV (a slow start's words, Picture in Picture) is checked
// in-process: AppFeaturesTests' Player.
// A few classes, so `scripts/test.sh player` runs them side by side.

/// The controls: each way the remote goes said at that edge — Up for Audio
/// & Subtitles, Down for More (Info, Up Next, Playback), Left and Right 10 s.
@MainActor
final class PlayerTests: XCTestCase {
    static let media = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "TestMedia").path

    /// Select with the controls down brings them up and the video plays on;
    /// with them up, Play/Pause pauses and plays.
    func testSelectShowsTheControlsAndPlayPauseWorks() {
        let app = launchPlaying(2, from: "/seek", extra: ["-startAt", "40"])     // past the intro; too long to end mid-test
        XCTAssertTrue(app.staticTexts["player.time"].exists(within: 8), "it didn't play")
        let remote = XCUIRemote.shared
        let edges = app.descendants(matching: .any)["edge.up"]
        _ = edges.exists(within: 2)                                  // up at the start…
        XCTAssertTrue(edges.gone(within: 3), "the controls didn't hide")         // …gone in 0.8 s (-quickTimers)
        remote.press(.select)
        XCTAssertTrue(edges.exists(within: 2), "Select didn't bring the controls up")
        XCTAssertTrue(app.descendants(matching: .any)["transport.playing"].exists, "Select paused instead of only showing the controls")
        remote.press(.playPause)                                     // paused, the controls stay up
        XCTAssertTrue(app.descendants(matching: .any)["transport.paused"].exists(within: 2), "Play/Pause didn't pause")
        remote.press(.playPause)
        XCTAssertTrue(app.descendants(matching: .any)["transport.playing"].exists(within: 2), "Play/Pause didn't resume")
    }

    /// Settings → Speakers Button: Speakers in More's Playback, and pressing
    /// it opens the system's speaker picker (not a card of ours).
    func testTheSpeakersButtonIsInPlayback() {
        let app = launchPlaying(2, from: "/seek", extra: ["-startAt", "40", "-player.speakersButton", "YES"])
        XCTAssertTrue(app.staticTexts["player.time"].exists(within: 8), "it didn't play")
        let remote = XCUIRemote.shared
        remote.press(.playPause)
        remote.press(.down)
        let playback = app.buttons["tab.playback"]
        XCTAssertTrue(playback.exists(within: 2), "Down didn't open More")
        XCTAssertTrue(remote.press(.right, in: app, atMost: 3) { playback.hasFocus }, "couldn't reach Playback")
        // The system's picker button, not one of ours: found by its identifier, any type.
        let speakers = app.descendants(matching: .any).matching(identifier: "control.speakers").firstMatch
        XCTAssertTrue(speakers.exists(within: 2), "no Speakers in Playback")
        remote.press(.down, in: app, atMost: 3) { speakers.hasFocus }
        print("focus on Speakers: \(app.focusSummary)")
        remote.press(.select)
        Thread.sleep(forTimeInterval: 1.5)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/speakers-picker.png"))
        }
    }

    /// With the controls gone, Up and Down only bring them back; the next
    /// press opens the panel.
    func testTheFirstPressShowsTheControls() {
        let app = launchPlaying(2, from: "/seek", extra: ["-startAt", "40"])
        XCTAssertTrue(app.staticTexts["player.time"].exists(within: 8), "it didn't play")
        let edges = app.descendants(matching: .any)["edge.up"]
        _ = edges.exists(within: 2)
        XCTAssertTrue(edges.gone(within: 3), "the controls didn't hide")
        let remote = XCUIRemote.shared
        remote.press(.down)
        XCTAssertTrue(edges.exists(within: 2), "Down didn't bring the controls up")
        XCTAssertFalse(app.descendants(matching: .any)["player.more"].exists, "Down opened More from an empty screen")
        remote.press(.down)
        XCTAssertTrue(app.descendants(matching: .any)["player.more"].exists(within: 2), "the second Down didn't open More")
    }

    /// Left alone in a panel while it plays, it goes: 20 s, 4 at
    /// -quickTimers' pace (the edges alone go in 0.8).
    func testAnIdlePanelStaysLongerThenGoes() {
        let app = launchPlaying(item: "series-001-s1-e2", extra: ["-startAt", "300"])   // 10 minutes, past its intro
        XCTAssertTrue(app.staticTexts["player.time"].exists(within: 8), "it didn't play")
        let remote = XCUIRemote.shared
        let more = app.descendants(matching: .any)["player.more"]
        remote.press(.down)                                          // the controls first (if they'd gone)…
        if !more.exists(within: 1) { remote.press(.down) }           // …then More
        XCTAssertTrue(more.exists(within: 2), "Down didn't open More")
        let opened = Date()
        XCTAssertTrue(more.gone(within: 8), "More stayed up, left alone")
        let stayed = Date().timeIntervalSince(opened)
        XCTAssertGreaterThan(stayed, 2, "More went too soon (after \(stayed) s)")
    }

    /// One press of Play/Pause pauses — and stays paused. (It could arrive
    /// twice, via SwiftUI and the Now Playing command, and cancel itself.)
    func testPlayPauseButtonPausesOnce() {
        let app = launchPlaying(6)   // H.264 + AAC MP4 → AVPlayer, Now Playing active
        XCTAssertTrue(waitFor(app.staticTexts["player.time"], label: { (Int($0) ?? 0) > 300 }, timeout: 8), "it didn't play")   // (the clip is 5 s)
        XCUIRemote.shared.press(.playPause)
        let pausedIcon = app.descendants(matching: .any)["transport.paused"]
        XCTAssertTrue(pausedIcon.exists(within: 1), "Play/Pause didn't pause")
        Thread.sleep(forTimeInterval: 0.6)           // a double-delivered press would resume by now
        XCTAssertTrue(pausedIcon.exists, "Pause undid itself")
    }

    /// More → Playback (the sleep timer, only here): it sets, and Down's
    /// edge then says when it stops.
    func testSleepTimerFromPlayback() {
        let app = launchPlaying(6)
        XCTAssertTrue(app.staticTexts["player.time"].exists(within: 8), "it didn't play")
        let remote = XCUIRemote.shared
        remote.press(.playPause)
        remote.press(.down)
        let playback = app.buttons["tab.playback"]
        XCTAssertTrue(playback.exists(within: 2), "Down didn't open More")
        XCTAssertTrue(remote.press(.right, in: app, atMost: 3) { playback.hasFocus }, "couldn't reach Playback")
        let fifteen = app.buttons["option.sleep-15"]
        XCTAssertTrue(fifteen.exists(within: 2), "no sleep options")
        remote.press(.select)                                        // into Playback: Off
        remote.press(.down, in: app, atMost: 4) { fifteen.hasFocus }
        remote.press(.select)
        let more = app.descendants(matching: .any)["edge.down"]
        more.wait { ($0.value as? String ?? "").contains("m") }
        XCTAssertTrue(["Stops in 15m", "Stops in 14m"].contains(more.value as? String ?? ""), "Down's edge doesn't say when it stops (\(more.value ?? "nil"))")
    }

    /// In the intro, the Right edge says Skip Intro, and Right skips it.
    func testRightSkipsTheIntro() {
        let app = launchPlaying(2, from: "/seek", extra: ["-startAt", "8"])       // the mock's intro: 0:05–0:35
        let time = app.staticTexts["player.time"]
        XCTAssertTrue(time.exists(within: 8), "it didn't play")
        let right = app.descendants(matching: .any)["edge.right"]
        XCTAssertTrue(right.wait(4) { $0.label.contains("Skip") }, "the Right edge doesn't offer Skip Intro (\(right.exists ? right.label : "none"))")
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitFor(time, label: { (Int($0) ?? 0) >= 34_000 }, timeout: 4), "Right didn't skip the intro (at \(time.label) ms)")
    }
}

/// Subtitles, as VLCKit reports them.
@MainActor
final class PlayerSubtitleTests: XCTestCase {
    /// MKV + ASS plays on VLCKit with subtitles on by default; Up opens
    /// Audio & Subtitles on the track playing, and VLCKit itself reports
    /// each change.
    func testSubtitlesOnByDefaultAndSelectableWithRemote() {
        let app = launchPlaying(1)   // MKV · H.264 + DTS + ASS → VLCKit
        let status = app.staticTexts["player.subtitles"]
        XCTAssertTrue(status.exists(within: 5))
        XCTAssertTrue(waitFor(status, label: { $0 != "off" }, timeout: 4), "No subtitle track on by default (VLCKit reports '\(status.label)')")

        let remote = XCUIRemote.shared
        remote.press(.playPause)                     // keep the 5 s clip from ending mid-test
        remote.press(.up)
        let off = app.buttons["option.sub-off"]
        let firstTrack = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'option.sub-' AND identifier != 'option.sub-off'")).firstMatch
        XCTAssertTrue(firstTrack.exists(within: 2), "Subtitle menu didn't open")
        XCTAssertTrue(firstTrack.waitForFocus(), "Focus should start on the selected subtitle track")

        remote.press(.up)
        XCTAssertTrue(off.waitForFocus(), "Up should move to 'Off'")
        remote.press(.select)
        XCTAssertTrue(waitFor(status, label: { $0 == "off" }, timeout: 2), "VLCKit still shows a subtitle after choosing Off")
        XCTAssertTrue(off.gone(within: 2), "choosing didn't close Audio & Subtitles")
        app.focusSettles(quiet: 0.2)                 // the card done closing
        remote.press(.up)                            // reopen
        XCTAssertTrue(off.exists(within: 2) && off.waitForFocus(2.5), "Reopened menu should focus the chosen option")
        remote.press(.down)
        remote.press(.select)
        XCTAssertTrue(waitFor(status, label: { $0 != "off" }, timeout: 2), "Subtitle didn't come back")
    }

    /// Memory running low while VLCKit draws ASS (forced: a threshold no
    /// device has): VLCKit lets go of the track and the server's WebVTT of
    /// it is drawn over the picture, saying so — playback carries on.
    func testLowMemorySwapsVLCKitsASSForPlainSubtitles() {
        let app = launchPlaying(1, extra: ["-memoryGuardAt", "100000"])   // MKV · H.264 + DTS + ASS → VLCKit
        XCTAssertTrue(app.staticTexts["player.notice"].exists(within: 6), "no notice of the swap")
        let status = app.staticTexts["player.subtitles"]
        XCTAssertTrue(waitFor(status, label: { $0 == "WebVTT" }, timeout: 2), "still VLCKit's subtitles ('\(status.label)')")
        XCTAssertTrue(app.staticTexts["subtitle.text"].exists(within: 3), "no plain words over the picture")
    }

    /// Subtitles → Find Subtitles: the server's subtitle search, best fit
    /// first (the hash match), and picking it puts it on at once.
    func testFindSubtitlesUsesTheBestMatch() throws {
        // The mock server's subtitle search; no ranking service (the device judges).
        let app = launchPlaying(1, extra: ["-searchEndpoint", "http://localhost:9/v1/interpret"])
        let status = app.staticTexts["player.subtitles"]
        XCTAssertTrue(status.exists(within: 5))
        let remote = XCUIRemote.shared
        remote.press(.playPause)
        remote.press(.up)
        let off = app.buttons["option.sub-off"]
        XCTAssertTrue(off.exists(within: 2), "Up didn't open Audio & Subtitles")
        for _ in 0..<4 where !off.hasFocus { remote.press(.up) }
        remote.press(.select)                                        // Off first, so a change is visible
        XCTAssertTrue(waitFor(status, label: { $0 == "off" }, timeout: 2))
        XCTAssertTrue(off.gone(within: 2))
        app.focusSettles(quiet: 0.2)
        remote.press(.up)
        let find = app.buttons["option.sub-find"]
        XCTAssertTrue(find.exists(within: 2), "no Find Subtitles")
        XCTAssertTrue(remote.press(.down, in: app, atMost: 8) { find.hasFocus }, "couldn't reach Find Subtitles")
        remote.press(.select)
        let best = app.buttons["option.found-os-1001"]
        XCTAssertTrue(best.exists(within: 8), "no results")
        // Menu steps back to the list (not out of the card), and in again.
        remote.press(.menu)
        XCTAssertTrue(find.exists(within: 2), "Menu from the results closed the card instead of going back to the list")
        remote.press(.down, in: app, atMost: 8) { find.hasFocus }
        remote.press(.select)
        XCTAssertTrue(best.exists(within: 8), "no results the second time")
        XCTAssertTrue(best.waitForFocus(2), "focus didn't land on the best match")
        XCTAssertTrue(best.label.contains("Best match"), "first result isn't marked: \(best.label)")
        remote.press(.select)
        XCTAssertTrue(waitFor(status, label: { $0 != "off" }, timeout: 5), "the found subtitle didn't come on (VLCKit reports '\(status.label)')")
    }
}

/// Scrubbing with clicks, on each backend.
@MainActor
final class PlayerScrubTests: XCTestCase {
    /// Pause, click right three times (the head moves +30 s), Select: playback
    /// resumes exactly at the head — on both backends. (Swipes are covered by
    /// TransportModelTests; XCUIRemote can't swipe.)
    func testScrubWithClicksResumesExactlyAtTheHeadOnVLCKit() { scrubResumesAtTheHead(clip: 0) }      // MKV → VLCKit
    func testScrubWithClicksResumesExactlyAtTheHeadOnAVPlayer() { scrubResumesAtTheHead(clip: 2) }    // MP4 → AVPlayer

    private func scrubResumesAtTheHead(clip: Int) {
        let app = launchPlaying(clip, from: "/seek")
        let time = app.staticTexts["player.time"], head = app.staticTexts["player.head"]
        XCTAssertTrue(waitFor(time, label: { (Int($0) ?? 0) > 1000 }, timeout: 8), "clip \(clip) didn't start")
        let remote = XCUIRemote.shared
        remote.press(.playPause)
        XCTAssertTrue(app.descendants(matching: .any)["transport.paused"].exists(within: 2), "clip \(clip): didn't pause")
        let paused = Int(time.label) ?? 0
        for _ in 0..<3 { remote.press(.right) }
        XCTAssertTrue(waitFor(head, label: { Int($0) == paused + 30_000 }, timeout: 2), "clip \(clip): head \(head.label), expected \(paused + 30_000)")
        XCTAssertTrue(app.descendants(matching: .any)["scrub.preview"].exists, "clip \(clip): no scrub preview")
        let target = Int(head.label) ?? 0
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["transport.playing"].exists(within: 5), "clip \(clip): didn't play")
        // Until the clock leaves where it paused, and has had a moment to settle at the head.
        waitUntil(3) { (Int(time.label) ?? 0) >= target - 600 }
        let now = Int(time.label) ?? 0
        XCTAssertTrue(now >= target - 600 && now <= target + 2_500, "clip \(clip): resumed at \(now) ms, head was \(target) ms")
    }
}

@MainActor
extension XCTestCase {
    /// The app playing `clip` of TestMedia/ (5 s each), or of TestMedia/seek
    /// (two minutes): its timers at a fifth, its mock on any free port.
    func launchPlaying(_ clip: Int, from folder: String = "", extra: [String] = []) -> XCUIApplication {
        launchPlaying(item: "media-\(clip)", from: folder, extra: extra)
    }

    func launchPlaying(item id: String, from folder: String = "", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-quickTimers", "-mockHTTP", "-mockPort", "0", "-mockMedia", PlayerTests.media + folder, "-autoplay", id] + extra
        app.launch()
        return app
    }

    fileprivate func waitFor(_ element: XCUIElement, label matches: (String) -> Bool, timeout: TimeInterval) -> Bool {
        element.wait(timeout) { matches($0.label) }
    }
}
