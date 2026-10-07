import XCTest

/// Screenshots of the player chrome for design review (not a pass/fail test):
/// `scripts/test.sh shots` → perf-results/shots/.
@MainActor
final class PlayerShots: XCTestCase {
    func testPlayerChrome() throws {
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockPort", "0", "-mockMedia", PlayerTests.media, "-autoplay", "media-1"]
        app.launch()
        func shot(_ name: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png")) }
        let remote = XCUIRemote.shared
        Thread.sleep(forTimeInterval: 1.2); shot("1-playing")
        remote.press(.select); Thread.sleep(forTimeInterval: 0.3); shot("2-paused")
        remote.press(.right); remote.press(.right); Thread.sleep(forTimeInterval: 1.5); shot("3-scrub")
        remote.press(.menu); Thread.sleep(forTimeInterval: 0.4)
        remote.press(.up); Thread.sleep(forTimeInterval: 0.5); shot("4-icons")
        remote.press(.select); Thread.sleep(forTimeInterval: 0.6); shot("5-subtitles")
        remote.press(.menu); remote.press(.right); remote.press(.select); Thread.sleep(forTimeInterval: 0.6); shot("6-audio")
        remote.press(.menu); remote.press(.right); remote.press(.select); Thread.sleep(forTimeInterval: 0.6); shot("7-playback")
        remote.press(.menu); remote.press(.right); remote.press(.select); Thread.sleep(forTimeInterval: 0.6); shot("8-info")
        remote.press(.menu); remote.press(.right); remote.press(.select); Thread.sleep(forTimeInterval: 0.8); shot("9-chapters")
    }

    /// The About band on an episode (with the next episode beside it).
    func testAboutBand() throws {
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-mockHTTP", "-mockPort", "0", "-mockMedia", PlayerTests.media, "-autoplay", "series-001-s1-e2"]
        app.launch()
        let remote = XCUIRemote.shared
        Thread.sleep(forTimeInterval: 2)
        remote.press(.select); Thread.sleep(forTimeInterval: 0.4)
        remote.press(.up); Thread.sleep(forTimeInterval: 0.5)
        for _ in 0..<3 { remote.press(.right) }
        remote.press(.select); Thread.sleep(forTimeInterval: 1.2)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/about-episode.png"))
    }
}
