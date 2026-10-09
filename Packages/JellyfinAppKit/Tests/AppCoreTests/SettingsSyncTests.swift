import Foundation
import Testing
@testable import AppCore

/// iCloud stands in for "your other devices": what they set arrives here,
/// and what belongs to this device stays put.
@MainActor
struct SettingsSyncTests {
    final class FakeStore: NSUbiquitousKeyValueStore, @unchecked Sendable {
        var values: [String: Any] = [:]
        override func object(forKey key: String) -> Any? { values[key] }
        override func set(_ value: Any?, forKey key: String) { values[key] = value }
        override func synchronize() -> Bool { true }
    }

    @Test func anotherDevicesChoicesArriveAndThisDevicesStay() throws {
        let defaults = try #require(UserDefaults(suiteName: "sync-\(UUID().uuidString)"))
        defaults.set(false, forKey: "playback.matchContent")             // this TV's own
        let store = FakeStore()
        store.values = ["subtitles.style": SubtitleStyle.allCases.last!.rawValue, "browse.hideSpoilers": false,
                        "playback.matchContent": true]                    // a device setting never syncs
        let sync = SettingsSync(defaults: defaults, store: store)
        sync.pull()
        let settings = AppSettings(defaults: defaults)
        settings.sync = sync
        #expect(settings.subtitleStyle == SubtitleStyle.allCases.last)
        #expect(settings.hideSpoilers == false)
        #expect(settings.matchContent == false)

        // A change here goes to iCloud; a device setting doesn't.
        settings.skipIntrosAutomatically = true
        settings.matchContent = true
        #expect(store.values["playback.autoSkipIntro"] as? Bool == true)
        #expect(store.values["playback.matchContent"] as? Bool == true)     // untouched: still the other device's
        settings.matchContent = false
        #expect(store.values["playback.matchContent"] as? Bool == true)

        // Another device's change, applied live.
        defaults.set(true, forKey: "browse.hideSpoilers")
        settings.reloadSynced()
        #expect(settings.hideSpoilers)
    }

    /// A launch argument (`-subtitles.mode off`, for one run) is never
    /// given to iCloud: it turned subtitles off on every Apple TV.
    @Test func aLaunchArgumentIsNeverSeededToICloud() throws {
        let defaults = try #require(UserDefaults(suiteName: "sync-\(UUID().uuidString)"))
        defaults.set("classic", forKey: "subtitles.style")                // saved on this device
        defaults.set("off", forKey: "subtitles.mode")                     // reads as a launch argument does
        let store = FakeStore()
        let sync = SettingsSync(defaults: defaults, store: store)
        sync.seed(arguments: ["subtitles.mode": "off"])
        #expect(store.values["subtitles.mode"] == nil, "the launch argument went to iCloud")
        #expect(store.values["subtitles.style"] as? String == "classic")
    }
}
