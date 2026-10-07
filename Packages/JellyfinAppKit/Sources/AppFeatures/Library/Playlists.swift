import AppCore
import DesignSystem
import Foundation
import Instrumentation
import JellyfinAPI
import SwiftUI

/// The server's playlists: the video ones (music doesn't play here), each
/// played through in its order.
nonisolated enum Playlists {
    static func list(library: String, client: JellyfinClient) async throws -> [BaseItem] {
        var q = ItemQuery(parentId: library, includeItemTypes: [.playlist], sortBy: ["SortName"], limit: 200)
        q.fields = ItemField.card + [.childCount]
        return try await client.items(q).items.filter { $0.mediaType != "Audio" }
    }

    /// "Three playlists."
    static func lede(_ list: [BaseItem]) -> String {
        let words = Editorial(userName: nil)
        let n = words.number(list.count)
        return (n.prefix(1).uppercased() + n.dropFirst()) + (list.count == 1 ? " playlist." : " playlists.")
    }

    /// Under a playlist's card: "6 items · about 4 hours".
    static func caption(_ playlist: BaseItem) -> String? {
        var parts: [String] = []
        if let n = playlist.childCount { parts.append(n == 1 ? "1 item" : "\(n) items") }
        if let ticks = playlist.runTimeTicks, ticks > 0 {
            parts.append(Editorial(userName: nil).roughly(Int(ticks / BaseItem.ticksPerSecond / 60)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Four episodes and two films, about four hours."
    static func lede(items: [BaseItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let words = Editorial(userName: nil)
        let episodes = items.filter { $0.kind == .episode }.count
        let films = items.filter { $0.kind == .movie }.count
        let other = items.count - episodes - films
        let parts = [(episodes, "episode", "episodes"), (films, "film", "films"), (other, "video", "videos")]
            .filter { $0.0 > 0 }.map { "\(words.number($0.0)) \($0.0 == 1 ? $0.1 : $0.2)" }
        let minutes = items.compactMap(\.runTimeTicks).reduce(0, +) / BaseItem.ticksPerSecond / 60
        let line = parts.joined(separator: " and ") + (minutes > 0 ? ", \(words.roughly(Int(minutes)))." : ".")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    /// Under an item on a playlist's page: "1. S1 · E3 · Name", "2. 1994".
    static func caption(_ item: BaseItem, at index: Int) -> String {
        let rest = item.kind == .episode
            ? [item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · ")
            : item.productionYear.map(String.init) ?? ""
        return "\(index + 1). " + rest
    }
}

/// A playlist's card: its art, its name, how many and how long.
struct PlaylistCard: View {
    let playlist: BaseItem
    let width: CGFloat
    @Environment(\.navigate) private var navigate

    var body: some View {
        LandscapeCard(playlist, width: width, caption: Playlists.caption(playlist)) { navigate(.item(playlist)) }
    }
}

/// "View all" from Home's Playlists row (or a Playlists library opened
/// anywhere): every video playlist.
struct PlaylistsPage: View {
    let library: BaseItem
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.pageWidth) private var width
    @State private var list: [BaseItem]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(library.name ?? "Playlists").font(.system(size: Layout.pageTitleSmall, weight: .bold)).foregroundStyle(theme.primaryText)
                    if let list, !list.isEmpty { Text(Playlists.lede(list)).font(.pageLede).foregroundStyle(theme.secondaryText) }
                }
                let columns = Layout.columns(width, minWidth: Layout.landscapeMin, max: 4)
                let cardWidth = Layout.cardWidth(width, columns: columns)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: Layout.cardSpacing, alignment: .top), count: columns),
                          alignment: .leading, spacing: Layout.shelfSpacing + 8) {
                    ForEach(list ?? []) { PlaylistCard(playlist: $0, width: cardWidth) }
                }
                .tvFocusSection()
                if list?.isEmpty == true {
                    Text("No video playlists yet. Make one in Jellyfin and it shows up here.").font(.detailText).foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 50)
        }
        .tvScrollClipDisabled()
        .background(theme.backgroundGradient.ignoresSafeArea())
        .hidesNavigationBar()
        .task {
            guard let client = app.session?.client else { return }
            list = (try? await Playlists.list(library: library.id, client: client)) ?? []
        }
    }
}

/// A playlist: Play (from the top) and Shuffle, then its items in order —
/// any one plays from there to the end.
struct PlaylistPage: View {
    let playlist: BaseItem
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.pageWidth) private var width
    @State private var items: [BaseItem]?
    @State private var details: BaseItem?
    @FocusState private var playFocused: Bool

    var body: some View {
        let items = items ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(details?.name ?? playlist.name ?? "Playlist").font(.system(size: Layout.pageTitleSmall, weight: .bold)).foregroundStyle(theme.primaryText)
                        .accessibilityIdentifier("playlist.title")
                    if let lede = Playlists.lede(items: items) { Text(lede).font(.pageLede).foregroundStyle(theme.secondaryText) }
                    HStack(spacing: Platform.isTV ? 24 : 12) {
                        Pill("Play", systemImage: "play.fill", size: .large, prominent: true, alwaysShowsTitle: true) { play(from: 0, in: items) }
                            .focused($playFocused)
                            .accessibilityIdentifier("playlist.play")
                        Pill("Shuffle", systemImage: "shuffle", size: .large, alwaysShowsTitle: true) { play(from: 0, in: items.shuffled()) }
                            .accessibilityIdentifier("playlist.shuffle")
                    }
                    .disabled(items.isEmpty)
                    .padding(.top, 6)
                }
                .tvFocusSection()
                let columns = Layout.columns(width, minWidth: Layout.landscapeMin, max: 4)
                let cardWidth = Layout.cardWidth(width, columns: columns)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: Layout.cardSpacing, alignment: .top), count: columns),
                          alignment: .leading, spacing: Layout.shelfSpacing + 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        LandscapeCard(item, width: cardWidth, kind: item.kind == .episode ? .still : .landscape, caption: Playlists.caption(item, at: i)) {
                            play(from: i, in: items)
                        }
                        .contextMenu { ItemContextMenu(item: item) }
                        .accessibilityIdentifier("playlist.item.\(i)")
                    }
                }
                .tvFocusSection()
                if self.items?.isEmpty == true {
                    Text("Nothing in this playlist yet.").font(.detailText).foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 50)
        }
        .tvScrollClipDisabled()
        .background(theme.backgroundGradient.ignoresSafeArea())
        .hidesNavigationBar()
        .defaultFocus($playFocused, true)
        .task {
            guard let client = app.session?.client else { return }
            async let full = try? client.item(id: playlist.id)
            self.items = (try? await client.playlistItems(id: playlist.id).items) ?? []
            details = await full
            if Platform.isTV { playFocused = true }
        }
    }

    /// From this one to the end, each in turn, from its start.
    private func play(from index: Int, in list: [BaseItem]) {
        guard list.indices.contains(index) else { return }
        TraceFile.write("playlist", "play \(playlist.name ?? playlist.id) from \(index + 1) of \(list.count)")
        app.play(list[index], resume: false, sequence: Array(list[(index + 1)...]))
    }
}
