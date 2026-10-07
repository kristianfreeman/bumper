import XCTest

// Waiting for what the app shows, never a fixed pause: each of these polls
// the accessibility snapshot every 50 ms until it holds, or the time's up.
// (A sleep stood in for "until it's there" and cost its full length every
// run; XCTest's own `waitForExistence` looks once a second, so even
// something already on its way cost a second.) Shared by the TV's and the
// phone's UI tests.

/// Until `condition` holds; false if it still doesn't at the deadline.
@MainActor @discardableResult
func waitUntil(_ timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { return false }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return true
}

extension XCUIElement {
    /// Until it's there: `waitForExistence`, looking every 50 ms.
    func exists(within timeout: TimeInterval) -> Bool { waitUntil(timeout) { exists } }

    /// Until it's gone.
    func gone(within timeout: TimeInterval) -> Bool { waitUntil(timeout) { !exists } }

    /// Until it's there and `condition` holds of it (its label, value, focus).
    @discardableResult
    func wait(_ timeout: TimeInterval = 3, until condition: (XCUIElement) -> Bool) -> Bool {
        waitUntil(timeout) { exists && condition(self) }
    }

    #if os(tvOS)
    @discardableResult
    func waitForFocus(_ timeout: TimeInterval = 2) -> Bool { wait(timeout) { $0.hasFocus } }
    #endif
}

#if os(tvOS)
extension XCUIApplication {
    /// Whatever has focus, read afresh each time it's asked.
    var focused: XCUIElement { descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true")) }

    /// What has focus, as words to compare and to print.
    var focusSummary: String {
        let f = focused
        return f.exists ? "\(f.identifier)|\(f.label)" : ""
    }
}

extension XCUIRemote {
    /// Presses `button` until `done` holds, at most `times`; after each
    /// press, waits for focus to move on before looking (not a fixed pause).
    @MainActor @discardableResult
    func press(_ button: Button, in app: XCUIApplication, atMost times: Int, until done: () -> Bool) -> Bool {
        for _ in 0..<times where !done() {
            let before = app.focusSummary
            press(button)
            waitUntil(1) { app.focusSummary != before }
        }
        return done()
    }
}
#endif
