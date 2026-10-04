import XCTest

/// Audiobooks end to end against the mock server: TestMedia/books, streamed
/// as MP3 over HTTP, decoded in-app (scripts/make-audiobook-media.sh).
@MainActor
final class AudiobookTests: XCTestCase {
    /// Plays and advances; Play/Pause toggles once; +30 s and Next Chapter
    /// move where they say; Smart Speed starts saving on the book's pauses.
    func testListenSkipChapterAndSmartSpeed() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockMedia", PlayerTests.media, "-reset", "-autoplay", "book-0"]
        app.launch()
        let position = app.staticTexts["audiobook.position"], state = app.staticTexts["audiobook.state"]
        let saved = app.staticTexts["audiobook.saved"], chapter = app.staticTexts["audiobook.chapter"]
        func ms(_ e: XCUIElement) -> Int { Int(e.label) ?? -1 }
        XCTAssertTrue(waitFor(position, timeout: 8) { (Int($0) ?? 0) > 800 }, "Book didn't start playing (position \(position.label))")
        XCTAssertEqual(state.label, "playing")

        let remote = XCUIRemote.shared
        remote.press(.playPause)
        XCTAssertTrue(waitFor(state, timeout: 2) { $0 == "paused" }, "Play/Pause didn't pause")
        Thread.sleep(forTimeInterval: 0.5)                     // a second press, not the same one twice
        remote.press(.playPause)
        XCTAssertTrue(waitFor(state, timeout: 2) { $0 == "playing" }, "Play/Pause didn't resume")

        let before = ms(position)
        remote.press(.right)                                   // play/pause → +30
        remote.press(.select)
        XCTAssertTrue(waitFor(position, timeout: 3) { (Int($0) ?? 0) >= before + 28_000 }, "+30 s went to \(position.label) from \(before)")
        XCTAssertTrue(chapter.label.hasPrefix("Chapter 2 of 3"), "after +30 s: \(chapter.label)")

        remote.press(.right)                                   // +30 → next chapter
        remote.press(.select)
        XCTAssertTrue(waitFor(chapter, timeout: 3) { $0.hasPrefix("Chapter 3 of 3") }, "Next Chapter: \(chapter.label)")

        remote.press(.down)                                    // options row
        let smart = app.buttons["audiobook.smartSpeed"]
        for _ in 0..<4 where !smart.hasFocus { remote.press(.left) }
        for _ in 0..<4 where !smart.hasFocus { remote.press(.right) }
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        XCTAssertTrue(smart.hasFocus, "couldn't reach Smart Speed (focus on '\(focused.label)' id=\(focused.identifier); smart exists \(smart.exists))")
        remote.press(.select)
        // Chapter 3 opens with "The pier was empty." and a 2 s pause.
        XCTAssertTrue(waitFor(saved, timeout: 8) { (Int($0) ?? 0) > 800 }, "Smart Speed saved \(saved.label) ms")
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
