import AVFoundation
import Instrumentation
import JellyfinAPI
import os

/// Series/movie theme music on detail pages: fades in quietly, loops, fades
/// out when leaving the page or starting playback. Keyed by the *owner*
/// (the series), so moving series → season → episode keeps the same song
/// playing instead of restarting it.
@MainActor
final class ThemeMusic {
    static let shared = ThemeMusic()

    private let player = AVPlayer()
    private var ownerId: String?
    private var fade: Task<Void, Never>?
    private var loopObserver: (any NSObjectProtocol)?
    private var statusObservation: NSKeyValueObservation?
    private nonisolated static let log = Perf.logger("theme-music")
    static let targetVolume: Float = 0.35

    private init() {
        player.volume = 0
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    /// Starts (or keeps) the theme for `item`. Cheap to call on every appear.
    func play(for item: BaseItem, client: JellyfinClient, online: Bool) async {
        let owner = item.seriesId ?? item.id
        if owner == ownerId, player.rate > 0 { return }          // already playing this show
        guard let url = await Self.themeURL(for: item, client: client, online: online) else {
            Self.log.info("No theme music for \(owner, privacy: .public)")
            return
        }
        ownerId = owner
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        }
        statusObservation = playerItem.observe(\.status) { item, _ in
            if item.status == .failed {
                Self.log.error("Theme music failed: \(item.error?.localizedDescription ?? "?", privacy: .public)")
            }
        }
        player.volume = 0
        player.play()
        Self.log.info("Theme music playing for \(owner, privacy: .public)")
        ramp(to: Self.targetVolume, over: .seconds(1.5))
    }

    /// The server's theme song (theme.mp3 next to the show, or one a plugin
    /// downloaded) — else, for TV, Plex's public theme archive by TVDB id,
    /// which is where Infuse/Plex get theirs. Most Jellyfin libraries have no
    /// local themes, so without the fallback most shows would be silent.
    static func themeURL(for item: BaseItem, client: JellyfinClient, online: Bool) async -> URL? {
        if let song = try? await client.themeSongs(itemId: item.id).first {
            log.info("Theme music from server: \(song.id, privacy: .public)")
            return client.universalAudioURL(itemId: song.id)
        }
        guard online, item.kind != .movie, let tvdb = await seriesTvdbId(item, client: client) else { return nil }
        log.info("Theme music from Plex archive: tvdb \(tvdb, privacy: .public)")
        return URL(string: "https://tvthemes.plexapp.com/\(tvdb).mp3")
    }

    private static func seriesTvdbId(_ item: BaseItem, client: JellyfinClient) async -> String? {
        if item.kind == .series { return item.providerIds?["Tvdb"] }
        guard let seriesId = item.seriesId else { return nil }
        return try? await client.item(id: seriesId, fields: [.providerIds]).providerIds?["Tvdb"]
    }

    /// Fades out and stops. Called when leaving a detail page (only if the
    /// song is still that page's — the next page may already own it) or when
    /// playback starts (`owner == nil`: always).
    func stop(owner: String? = nil, fadeOut: Duration = .milliseconds(700)) {
        guard player.currentItem != nil, owner == nil || owner == ownerId else { return }
        ownerId = nil
        ramp(to: 0, over: fadeOut) { [player] in
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private func ramp(to target: Float, over duration: Duration, then done: (@MainActor () -> Void)? = nil) {
        fade?.cancel()
        let start = player.volume
        fade = Task { [player] in
            let steps = 20
            for i in 1...steps {
                try? await Task.sleep(for: duration / steps)
                if Task.isCancelled { return }
                player.volume = start + (target - start) * Float(i) / Float(steps)
            }
            done?()
        }
    }
}
