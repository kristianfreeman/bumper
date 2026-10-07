#if os(macOS)                    // in-process view tests: the Mac's `swift test`
@testable import AppFeatures
import AppCore
import Testing

extension OnScreen {
    /// Settings off the TV, a form of switches and menus (UITests/SettingsTests:
    /// the TV's tiles and their focus stay there).
    @Suite("Settings")
    struct Settings {
        @Test func aSwitchFlipsTheSettingAndShowsIt() async throws {
            let screen = Screen(route: "settings:root")
            let before = screen.app.settings.autoplayNextEpisode
            let toggle = try await screen.wait(for: "setting.autoplay")
            try await screen.press("setting.autoplay")
            try await screen.waitUntil("the setting to flip") { screen.app.settings.autoplayNextEpisode != before }
            try await screen.wait(for: "setting.autoplay") { $0.value != toggle.value }
        }
    }
}
#endif
