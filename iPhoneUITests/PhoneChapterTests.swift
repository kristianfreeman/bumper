import XCTest

/// Chapters and slow starts on the iPhone, on the 20-minute clip (the
/// mock's chapters: 5:00 "The Harbour at Night", 10:00 "Chapter 03",
/// 15:00 "Landfall").
@MainActor
final class PhoneChapterTests: XCTestCase {
    static let media = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "TestMedia/long").path

    /// Upright, a row of them under the picture (tap one to go there); on
    /// its side, a menu beside the timeline.
    func testChaptersInThePanelAndTheMenu() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-reset", "-mockMedia", Self.media, "-autoplay", "media-0"]
        app.launch()
        let time = app.staticTexts["player.time"]
        XCTAssertTrue(waitFor(time, timeout: 10) { (Int($0) ?? 0) > 500 }, "it didn't play")
        let harbour = app.buttons["panel.chapter.1"]
        XCTAssertTrue(harbour.waitForExistence(timeout: 5), "no chapters under the picture")
        harbour.tap()
        XCTAssertTrue(waitFor(time, timeout: 5) { abs((Int($0) ?? 0) - 300_000) < 3_000 }, "didn't go to 5:00 (at \(time.label) ms)")
        XCTAssertTrue(waitFor(harbour, timeout: 2) { _ in harbour.value as? String == "playing" }, "the chapter playing isn't marked")

        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        let menu = app.buttons["control.chapters"]
        if !menu.exists { app.otherElements["player.surface"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(menu.waitForExistence(timeout: 2), "no Chapters beside the timeline")
        menu.tap()
        let landfall = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Landfall'")).firstMatch
        XCTAssertTrue(landfall.waitForExistence(timeout: 2), "the Chapters menu didn't open")
        landfall.tap()
        XCTAssertTrue(waitFor(time, timeout: 5) { abs((Int($0) ?? 0) - 900_000) < 3_000 }, "didn't go to 15:00 (at \(time.label) ms)")
        XCUIDevice.shared.orientation = .portrait
    }

    /// Resuming with every media request 1.5 s late: it says where it's going.
    func testSlowStartSaysWhereItsGoing() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-reset", "-mockMedia", Self.media, "-mediaLatency", "1500",
                               "-autoplay", "media-0", "-startAt", "642"]
        app.launch()
        let message = app.staticTexts["player.startMessage"]
        XCTAssertTrue(waitFor(message, timeout: 12) { $0 == "Getting to 10:42…" }, "no message (\(message.exists ? message.label : "none"))")
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
