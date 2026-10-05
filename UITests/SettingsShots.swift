import XCTest

/// Screenshots of every settings page, top and scrolled, for design review:
/// `scripts/test.sh shots` → perf-results/shots/.
@MainActor
final class SettingsShots: XCTestCase {
    func testSettingsPages() throws {
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png")) }
        let remote = XCUIRemote.shared
        for page in ["root", "subtitles", "look", "about", "themes"] {
            let app = XCUIApplication()
            app.launchArguments = ["-mock", "-route", "settings:\(page)"]
            app.launch()
            Thread.sleep(forTimeInterval: 1.5); shot("settings-\(page)-1")
            for _ in 0..<7 { remote.press(.down) }
            Thread.sleep(forTimeInterval: 0.8); shot("settings-\(page)-2")
            app.terminate()
        }
    }
}
