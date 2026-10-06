import XCTest

/// Downloads on the iPhone, against the mock server: Download on a film's
/// page → Downloaded; it's on the Downloads tab; removing it empties it.
@MainActor
final class PhoneDownloadTests: XCTestCase {
    func testDownloadAFilmAndRemoveIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        let download = app.buttons["detail.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 10), "no Download button on the film's page")
        download.tap()
        let done = app.buttons.matching(NSPredicate(format: "label == 'Downloaded'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 20), "never finished downloading (button: \(download.label))")
        shot(app, "detail-downloaded")

        // Downloads (in the profile menu: the iPhone's tab bar holds Home,
        // the libraries and Search) lists it.
        app.terminate()
        app.launchArguments = ["-mock"]                                 // same downloads, Home first
        app.launch()
        let avatar = app.buttons["profile.avatar"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 8), "no profile menu")
        avatar.tap()
        let item = app.buttons["menu.downloads"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "no Downloads in the profile menu")
        item.tap()
        let card = app.buttons["downloads.film.movie-0001"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the film isn't on the Downloads page")
        shot(app, "downloads-page")
        card.press(forDuration: 1.2)
        let remove = app.buttons["Remove Download"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "removing didn't take it off the page")
    }

    static let media = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "TestMedia").path

    /// Downloaded clips play in the same player: an MP4 (AVPlayer) and an
    /// MKV with DTS and ASS subtitles (VLCKit), from the file on the device.
    func testDownloadedFilesPlay() {
        for id in ["media-6", "media-1"] {
            let app = XCUIApplication()
            app.launchArguments = ["-mock", "-reset", "-mockMedia", Self.media, "-route", "item:\(id)"]
            app.launch()
            let download = app.buttons["detail.download"]
            XCTAssertTrue(download.waitForExistence(timeout: 10), "\(id): no Download button")
            download.tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Downloaded'")).firstMatch.waitForExistence(timeout: 60), "\(id): never finished downloading")
            app.buttons["detail.play"].tap()
            XCTAssertTrue(app.staticTexts["player.time"].waitForExistence(timeout: 10), "\(id): the downloaded file didn't play")
            Thread.sleep(forTimeInterval: 2)
            shot(app, "playing-\(id)")
            app.terminate()
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
