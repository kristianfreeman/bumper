public import Foundation

/// Your preferences on every device on the same iCloud account — both Apple
/// TVs, the iPhone, the iPad, the Mac (one app ID, one iCloud key-value
/// store). Only what's yours syncs (subtitles, what plays next, spoilers,
/// the theme, hidden libraries); what belongs to a device stays on it (its
/// player, bitrate, frame-rate matching, receiver, remote, downloads).
///
/// iCloud wins at launch (another device changed it last), so a new TV
/// starts as you've set things up; a change anywhere arrives everywhere.
@MainActor
public final class SettingsSync {
    public static let keys: Set<String> = [
        "subtitles.mode", "subtitles.scale", "subtitles.style", "subtitles.font",
        "playback.autoplayNext", "playback.autoSkipIntro", "playback.disableTranscoding",
        "browse.hideSpoilers", "browse.hiddenLibraries",
        "detail.themeMusic", "detail.themeMusicMovies", "detail.themeMusicOnline",
        "appearance.theme",
        "audiobooks.rate", "audiobooks.smartSpeed",
    ]

    private let store: NSUbiquitousKeyValueStore
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    /// Called (on the main actor) after another device's change lands in `defaults`.
    public var onChange: (() -> Void)?

    public init(defaults: UserDefaults, store: NSUbiquitousKeyValueStore = .default) {
        self.defaults = defaults
        self.store = store
    }

    /// Before the settings are read: iCloud's values into this device's.
    public func pull() {
        store.synchronize()
        for key in Self.keys {
            if let value = store.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    /// The first device to sync gives iCloud what it has (set before syncing
    /// existed), so the others start from it.
    public func seed() {
        for key in Self.keys where store.object(forKey: key) == nil {
            if let value = defaults.object(forKey: key) { store.set(value, forKey: key) }
        }
    }

    public func push(_ value: Any?, forKey key: String) {
        guard Self.keys.contains(key) else { return }
        store.set(value, forKey: key)
    }

    /// Another device's changes, as they arrive.
    public func start() {
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                          object: store, queue: .main) { [weak self] note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                var any = false
                for key in changed where Self.keys.contains(key) {
                    self.defaults.set(self.store.object(forKey: key), forKey: key)
                    any = true
                }
                if any { self.onChange?() }
            }
        }
        store.synchronize()
    }
}
