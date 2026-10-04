#if os(tvOS)
import AppCore
import Companion
import DesignSystem
import Foundation
import Instrumentation
import JellyfinAPI
import UIKit

/// What's playing, for the companion app.
struct NowPlayingInfo: Equatable {
    var item: BaseItem
    var position: Double
    var duration: Double
    var paused: Bool
}

/// The TV's side of the iPhone companion: advertises the TV on the local
/// network, keeps phones up to date (what's focused, what's playing,
/// Tonight), and carries out what they ask.
@MainActor
final class CompanionBridge {
    private unowned let app: AppModel
    private let host: CompanionHost
    private var ticker: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        let name = UIDevice.current.name
        host = CompanionHost(name: name.isEmpty || name == "Apple TV" ? "\(Brand.displayName) on Apple TV" : name)
    }

    func start() {
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
    }

    private func publish() {
        guard let session = app.session else { return }
        let client = session.client
        let state = CompanionState(
            tvName: UIDevice.current.name,
            userName: session.account.userName,
            focused: app.focusedItem.map { Self.item($0, client: client) },
            playing: app.nowPlaying.map { CompanionNowPlaying(item: Self.item($0.item, client: client), position: $0.position, duration: $0.duration, paused: $0.paused) }
                ?? app.audiobook.map { CompanionNowPlaying(item: Self.item($0.book.card, client: client), position: $0.position, duration: $0.book.duration, paused: !$0.isPlaying) },
            tonight: app.tonight.timeline.map { CompanionPlanEntry(item: Self.item($0.entry.item, client: client), start: $0.start, suggested: $0.entry.ambient, overruns: $0.overruns) },
            doneBy: app.tonight.plan.doneBy,
            tonightSummary: TonightWords.summary(app.tonight))
        host.publish(state)
    }

    private func handle(_ command: CompanionCommand, from connection: CompanionConnection) async {
        TraceFile.write("companion", "command \(command)")
        guard let client = app.session?.client else { return }
        switch command {
        case .play(let id):
            if let item = try? await client.item(id: id) { app.play(item) }
        case .addToTonight(let id):
            if let item = try? await client.item(id: id) { app.tonight.add(item) }
        case .removeFromTonight(let id):
            app.tonight.remove(id)
        case .moveInTonight(let id, let by):
            app.tonight.move(id, by: by)
        case .setDoneBy(let date):
            app.tonight.setDoneBy(date)
        case .playPause:
            if let book = app.audiobook { book.togglePlayPause() } else { NotificationCenter.default.post(name: .companionPlayPause, object: nil) }
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
#endif
