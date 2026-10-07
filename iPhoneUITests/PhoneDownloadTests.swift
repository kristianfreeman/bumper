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
        XCTAssertTrue(download.exists(within: 10), "no Download button on the film's page")
        download.tap()
        let done = app.buttons.matching(NSPredicate(format: "label == 'Downloaded'")).firstMatch
        XCTAssertTrue(done.exists(within: 20), "never finished downloading (button: \(download.label))")
        shot(app, "detail-downloaded")

        // Downloads (in the profile menu: the iPhone's tab bar holds Home,
        // the libraries and Search) lists it.
        app.terminate()
        app.launchArguments = ["-mock"]                                 // same downloads, Home first
        app.launch()
        let avatar = app.buttons["profile.avatar"]
        XCTAssertTrue(avatar.exists(within: 8), "no profile menu")
        avatar.tap()
        let item = app.buttons["menu.downloads"]
        XCTAssertTrue(item.exists(within: 3), "no Downloads in the profile menu")
        item.tap()
        let card = app.buttons["downloads.film.movie-0001"]
        XCTAssertTrue(card.exists(within: 5), "the film isn't on the Downloads page")
        shot(app, "downloads-page")
        card.press(forDuration: 1.2)
        let remove = app.buttons["Remove Download"]
        XCTAssertTrue(remove.exists(within: 3))
        remove.tap()
        XCTAssertTrue(card.gone(within: 5), "removing didn't take it off the page")
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
            XCTAssertTrue(download.exists(within: 10), "\(id): no Download button")
            download.tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Downloaded'")).firstMatch.exists(within: 60), "\(id): never finished downloading")
            app.buttons["detail.play"].tap()
            let time = app.staticTexts["player.time"]
            XCTAssertTrue(time.exists(within: 10), "\(id): the downloaded file didn't play")
            time.wait(5) { (Int($0.label) ?? 0) > 1_000 }                       // a picture to show
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
