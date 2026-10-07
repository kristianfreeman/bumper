import XCTest

/// Audiobook screens for design review (`scripts/test.sh shots`).
@MainActor
final class BookShots: XCTestCase {
    func testBookScreens() throws {
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png")) }
        let app = XCUIApplication()
        for (name, args) in [("books-library", ["-route", "books:view-books"]), ("books-detail", ["-route", "audiobook:book-0"]), ("books-playing", ["-autoplay", "book-0"])] {
            app.launchArguments = ["-mock", "-mockHTTP", "-mockPort", "0", "-mockMedia", PlayerTests.media, "-reset"] + args
            app.launch()
            Thread.sleep(forTimeInterval: 3)
            shot(name)
            if name == "books-playing" {
                XCUIRemote.shared.press(.down); XCUIRemote.shared.press(.right); XCUIRemote.shared.press(.right); XCUIRemote.shared.press(.right)
                XCUIRemote.shared.press(.select); Thread.sleep(forTimeInterval: 1); shot("books-chapters")
            }
            app.terminate()
        }
    }
}
