#if os(macOS)                    // in-process view tests: the Mac's `swift test`
@testable import AppFeatures
import AppCore
import SwiftUI
import Testing

extension OnScreen {
    /// The Queue (UITests/QueueTests: reaching the button with the remote
    /// stays there).
    @Suite("Queue")
    struct Queue {
        @Test func addingToTheQueueFromAPageThenItLeadsHome() async throws {
            let page = Screen(route: "item:movie-0001")
            try await page.press("detail.queue")
            try await page.wait(for: "detail.queue") { $0.text == "In Queue" }
            #expect(page.app.queue.contains("movie-0001"))

            let home = page.relaunch { _ in RoutedStack { HomeView() } }
            try await home.wait(for: "collection.queue")
            try await home.wait(for: "queue.play")
            try await home.wait(forAny: "card.queue.")
        }
    }
}
#endif
