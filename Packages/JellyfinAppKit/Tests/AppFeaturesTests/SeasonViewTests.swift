#if os(macOS)                    // in-process view tests: the Mac's `swift test`
@testable import AppFeatures
import Testing

extension OnScreen {
    /// A show's page (UITests/SeasonTests: the season bar following focus
    /// along the episodes stays there).
    @Suite("Seasons")
    struct Seasons {
        @Test func anEpisodeOpensInItsShowInItsSeason() async throws {
            let screen = Screen(route: "item:series-003-s2-e4")
            try await screen.wait(for: "season.2") { $0.isSelected }
            #expect(screen.element("season.1")?.isSelected == false)
            #expect(screen.elements.contains { $0.text.hasPrefix("S2 · E4") }, "the header isn't the episode")
        }

        @Test func pickingASeasonSelectsIt() async throws {
            let screen = Screen(route: "item:series-003")
            try await screen.wait(for: "season.1") { $0.isSelected }
            try await screen.press("season.4")
            try await screen.wait(for: "season.4") { $0.isSelected }
            #expect(screen.element("season.1")?.isSelected == false)
        }
    }
}
#endif
