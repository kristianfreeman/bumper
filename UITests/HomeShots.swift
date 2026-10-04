import XCTest

/// Home and a library page, row by row, for design review (`scripts/test.sh shots`).
@MainActor
final class HomeShots: XCTestCase {
    /// Bumper Light (any theme: `-appearance.theme <id>` sets it for one launch).
    func testHomeLight() throws {
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset", "-appearance.theme", "bumper-light"]
        app.launch()
        Thread.sleep(forTimeInterval: 2.5)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/home-light.png"))
        XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/home-light-2.png"))
    }

    func testHomeRows() throws {
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png")) }
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-reset"]
        app.launch()
        Thread.sleep(forTimeInterval: 2); shot("home-1")
        XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1); shot("home-2")
        XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1); shot("home-3")
        XCUIRemote.shared.press(.up); XCUIRemote.shared.press(.up)
        for _ in 0..<3 { XCUIRemote.shared.press(.right) }
        XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 0.8); shot("home-corner")
        app.terminate()
        app.launchArguments = ["-mock", "-reset", "-route", "item:movie-0001"]
        app.launch()
        Thread.sleep(forTimeInterval: 2); shot("detail-1")
        XCUIRemote.shared.press(.right); Thread.sleep(forTimeInterval: 0.8); shot("detail-2")
        app.terminate()
        app.launchArguments = ["-mock", "-reset", "-route", "library:view-movies"]
        app.launch()
        Thread.sleep(forTimeInterval: 2); shot("library-1")
        XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 1); shot("library-2")
    }
}
