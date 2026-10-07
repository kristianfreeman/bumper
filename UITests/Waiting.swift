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
    @discardableResult
    func exists(within timeout: TimeInterval) -> Bool { waitUntil(timeout) { exists } }

    /// Until it's gone.
    @discardableResult
    func gone(within timeout: TimeInterval) -> Bool { waitUntil(timeout) { !exists } }

    /// Until it's there and has stopped moving (the same frame for `quiet`):
    /// a page done pushing in, a scroll come to rest. A tap or a press
    /// while it's still on its way can land nowhere.
    @discardableResult
    func settles(_ timeout: TimeInterval = 3, quiet: TimeInterval = 0.25) -> Bool {
        var last = CGRect.null, since = Date()
        return waitUntil(timeout) {
            guard let now = (try? snapshot())?.frame else { last = .null; return false }
            if now != last { last = now; since = Date() }
            return Date().timeIntervalSince(since) >= quiet
        }
    }

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
    /// Whatever has focus, looked up afresh on each use.
    var focused: XCUIElement { descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true")) }

    /// What has focus and where it is, in one look ("" if nothing has):
    /// to tell when it's moved, or stopped moving.
    var focusSummary: String {
        guard let f = try? focused.snapshot() else { return "" }
        return "\(f.identifier)|\(f.label)|\(f.frame)"
    }

    /// Until something has focus and it's stopped moving (the same element,
    /// in the same place, for `quiet`): after a launch, or a press that
    /// scrolls the page.
    @discardableResult
    func focusSettles(_ timeout: TimeInterval = 5, quiet: TimeInterval = 0.3) -> Bool {
        var last = "", since = Date()
        return waitUntil(timeout) {
            let now = focusSummary
            if now != last { last = now; since = Date() }
            return !now.isEmpty && Date().timeIntervalSince(since) >= quiet
        }
    }
}

extension XCUIRemote {
    /// One press, then until focus moves (up to `timeout`): instead of a
    /// pause before looking at where it went.
    @MainActor @discardableResult
    func press(_ button: Button, movingFocusIn app: XCUIApplication, timeout: TimeInterval = 1.5) -> Bool {
        let before = app.focusSummary
        press(button)
        return waitUntil(timeout) { app.focusSummary != before }
    }

    /// Presses `button` until `done` holds, at most `times`, letting focus
    /// move after each press before looking.
    @MainActor @discardableResult
    func press(_ button: Button, in app: XCUIApplication, atMost times: Int, until done: () -> Bool) -> Bool {
        for _ in 0..<times where !done() { press(button, movingFocusIn: app) }
        return done()
    }
}
#endif
