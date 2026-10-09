import AppCore
import Companion
import DesignSystem
import Foundation
import Instrumentation
import JellyfinAPI
import PlaybackCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// What's playing, for the companion app.
struct NowPlayingInfo: Equatable {
    var item: BaseItem
    var position: Double
    var duration: Double
    var paused: Bool
}

/// The TV's side of the iPhone companion: advertises the TV on the local
/// network, keeps phones up to date (what's focused, what's playing,
/// Queue), and carries out what they ask.
@MainActor
final class CompanionBridge {
    private unowned let app: AppModel
    private let host: CompanionHost
    private var ticker: Task<Void, Never>?
    private var lastPlaying: CompanionNowPlaying?

    static var deviceName: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }

    init(app: AppModel) {
        self.app = app
        let name = Self.deviceName
        // Apps only see "Apple TV" for the device's name: advertise without
        // one, and the system uses the room ("Living Room") for us.
        host = CompanionHost(name: name.isEmpty || name == "Apple TV" ? nil : name)
    }

    func start() {
        guard ticker == nil else { return }
        host.onLog = { TraceFile.write("companion", $0) }
        host.onCommand = { [weak self] command, connection in
            Task { @MainActor in await self?.handle(command, from: connection) }
        }
        host.start()
        // Changes are cheap to compare: build the state twice a second; the
        // host only sends it when it differs.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.publish()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        TraceFile.write("companion", "remote on")
    }

    /// Settings → Remote off: no longer on the network; phones drop.
    func stop() {
        guard let ticker else { return }
        ticker.cancel()
        self.ticker = nil
        host.stop()
        TraceFile.write("companion", "remote off")
    }

    private func publish() {
        guard let session = app.session else { return }
        let client = session.client
        let state = CompanionState(
            tvName: Self.deviceName,
            userName: session.account.userName,
            focused: app.focusedItem.map { Self.item($0, client: client) },
            playing: app.nowPlaying.map { video(playing: $0, client: client) }
                ?? app.audiobook.map { CompanionNowPlaying(item: Self.item($0.book.card, client: client), position: $0.position, duration: $0.book.duration, paused: !$0.isPlaying) },
            queue: app.queue.timeline.map { CompanionPlanEntry(item: Self.item($0.entry.item, client: client), start: $0.start, suggested: $0.entry.ambient, overruns: $0.overruns) },
            doneBy: app.queue.plan.doneBy,
            queueSummary: QueueWords.summary(app.queue))
        if let p = state.playing, p != lastPlaying {
            if Int(p.position) / 10 != Int(lastPlaying?.position ?? -10) / 10 || p.paused != lastPlaying?.paused {
                TraceFile.write("companion", "playing \(p.item.title) at \(Int(p.position)) of \(Int(p.duration)) s\(p.paused ? ", paused" : "")")
            }
            lastPlaying = p
        }
        host.publish(state)
    }

    /// What's on, with what the phone's now-playing sheet steers: tracks,
    /// Untracked, the sleep timer, and what comes next.
    private func video(playing info: NowPlayingInfo, client: JellyfinClient) -> CompanionNowPlaying {
        var p = CompanionNowPlaying(item: Self.item(info.item, client: client), position: info.position, duration: info.duration, paused: info.paused)
        p.backdropURL = ArtworkSource.resolve(info.item, .backdrop)?.request(client: client, pixelWidth: 1200).url
        p.kind = info.item.kind == .episode ? "episode" : info.item.kind == .movie ? "film" : nil
        let timer = app.sleepTimer
        p.sleep = switch timer.mode {
        case .off: .off
        case .minutes(let m): .minutes(m)
        case .endOfItem: .endOfItem
        }
        p.sleepLabel = timer.shortLabel
        guard let player = app.player else { return p }
        p.subtitles = player.subtitleOptions.map { CompanionTrack(id: $0.index, title: MenuCard.trackName($0), detail: MenuCard.trackNote($0)) }
        p.subtitle = player.selectedSubtitle
        p.subtitleSearch = switch player.subtitleSearch {
        case .idle: nil
        case .searching: .searching
        case .results(let found):
            .results(found.enumerated().map { i, sub in CompanionFoundSubtitle(id: sub.id, name: sub.name, detail: FoundSubtitles.detail(sub, best: i == 0)) })
        case .failed(let message): .failed(message)
        }
        p.audio = player.audioOptions.map { CompanionTrack(id: $0.id, title: $0.title, detail: $0.detail) }
        p.audioTrack = player.engine?.selectedAudioTrack
        p.untracked = player.isBackground
        // Only what you've lined up: none, and the remote shows no Up Next.
        p.upNext = player.chosenUpNext.prefix(6).map { Self.item($0, client: client) }
        return p
    }

    private func handle(_ command: CompanionCommand, from connection: CompanionConnection) async {
        TraceFile.write("companion", "command \(command)")
        guard let client = app.session?.client else { return }
        switch command {
        case .play(let id):
            if let item = try? await client.item(id: id) { app.play(item) }
        case .playItem(let id, let resume, let background):
            guard let item = try? await client.item(id: id) else { break }
            if background { app.playInBackground(item) } else { app.play(item, resume: resume) }
        case .addToQueue(let id):
            if let item = try? await client.item(id: id) { app.queue.add(item) }
        case .removeFromQueue(let id):
            app.queue.remove(id)
        case .moveInQueue(let id, let by):
            app.queue.move(id, by: by)
        case .setDoneBy(let date):
            app.queue.setDoneBy(date)
        case .playPause:
            if let book = app.audiobook { book.togglePlayPause() } else { NotificationCenter.default.post(name: .companionPlayPause, object: nil) }
        case .seek(let seconds):
            await app.player?.seek(to: .seconds(seconds))
        case .skip(let seconds):
            await app.player?.skip(by: .seconds(seconds))
        case .selectSubtitle(let index):
            await app.player?.selectSubtitle(index)
        case .findSubtitles:
            await app.player?.findSubtitles()
        case .useFoundSubtitle(let id):
            if let player = app.player, case .results(let found) = player.subtitleSearch, let sub = found.first(where: { $0.id == id }) {
                await player.use(sub)                        // a found one becomes a track of the item, and on
                if player.foundSubtitle?.id == sub.id { player.subtitleSearch = .idle }   // (a failure stays, to say why)
            }
        case .cancelSubtitleSearch:
            app.player?.subtitleSearch = .idle
        case .selectAudio(let id):
            await app.player?.selectAudio(id)
        case .setUntracked(let on):
            app.player?.setBackground(on)
        case .setSleep(let choice):
            switch choice {
            case .off: app.sleepTimer.reset()
            case .minutes(let m): app.sleepTimer.set(.minutes(m))
            case .endOfItem: app.sleepTimer.set(.endOfItem)
            }
        case .search(let words):
            var q = ItemQuery(includeItemTypes: [.movie, .series], limit: 24)
            q.searchTerm = words
            let items = (try? await client.items(q).items) ?? []
            connection.send(.results(query: words, items: items.map { Self.item($0, client: client) }, understood: nil))
        case .ask(let words):
            var filter = CollectionFilter(base: ItemQuery(includeItemTypes: [.movie, .series], limit: 24), libraryName: "Everything")
            var changed: [CollectionFilter.Part] = []
            switch await app.search.understand(words, in: filter) {
            case .filter(let next, let parts, _): filter = next; changed = parts
            case .title(let term): filter.searchTerm = term
            }
            var q = filter.query
            q.limit = 60
            let items = ((try? await client.items(q).items) ?? []).filter { filter.matches($0) }.prefix(24)
            let understood = changed.isEmpty ? nil : changed.map(filter.text).joined(separator: ", ")
            connection.send(.results(query: words, items: items.map { Self.item($0, client: client) }, understood: understood))
        }
        publish()
    }

    static func item(_ item: BaseItem, client: JellyfinClient) -> CompanionItem {
        var subtitle: [String] = []
        if let series = item.seriesName {
            subtitle.append(series)
            if let s = item.parentIndexNumber, let e = item.indexNumber { subtitle.append("S\(s) E\(e)") }
        } else if let year = item.productionYear {
            subtitle.append(String(year))
        }
        let minutes = item.runTimeTicks.map { Int($0 / BaseItem.ticksPerSecond / 60) }
        if let minutes, minutes > 0 { subtitle.append(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min") }
        let image = (ArtworkSource.resolve(item, .landscape) ?? ArtworkSource.resolve(item, .poster))?.request(client: client, pixelWidth: 800).url
        return CompanionItem(id: item.id, title: item.seriesName == nil ? item.name ?? "" : item.name ?? item.seriesName ?? "",
                             subtitle: subtitle.joined(separator: " · "), overview: item.overview, imageURL: image, minutes: minutes)
    }
}

extension Notification.Name {
    static let companionPlayPause = Notification.Name("companion.playPause")
}
