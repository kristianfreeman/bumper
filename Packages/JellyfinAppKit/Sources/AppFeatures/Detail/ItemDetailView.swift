import AppCore
import DesignSystem
import Instrumentation
import JellyfinAPI
import Observation
import PlaybackCore
import SwiftUI

@MainActor
@Observable
final class DetailModel {
    var item: BaseItem
    private(set) var seasons: [BaseItem] = []
    private(set) var episodes: [BaseItem] = []
    var selectedSeason: String?
    private(set) var nextUp: BaseItem?
    private(set) var similar: [BaseItem] = []
    /// Series page: the episode the header describes and Play plays — Next
    /// Up at first, then whichever episode card has focus.
    var selectedEpisode: BaseItem?

    init(item: BaseItem) { self.item = item }

    func load(client: JellyfinClient) async {
        // Instant paint: prefetched on focus, else last-known from disk.
        let hit = DetailPrefetcher.shared.freshItem(item.id)
        Metrics.shared.record("detail.prefetchHit", value: hit == nil ? 0 : 1)
        if let fresh = hit {
            item = fresh
        } else if let cached = await ContentCache.shared.value(BaseItem.self, for: DetailPrefetcher.cacheKey(item.id)) {
            item = cached
        }
        await Perf.measure("detail.load", .detailLoad) {
            let id = item.id
            let similarId = item.kind == .episode ? (item.seriesId ?? id) : id
            async let full = try? client.item(id: id)
            async let similar = try? client.similar(to: similarId)
            if item.kind == .series {
                async let seasons = try? client.seasons(seriesId: id)
                async let next = try? client.nextUp(limit: 1, seriesId: id)
                self.seasons = await seasons?.items ?? []
                nextUp = await next?.items.first
                selectedSeason = nextUp?.seasonId ?? self.seasons.first?.id
                await loadEpisodes(client: client)
            }
            if let full = await full {
                item = full
                DetailPrefetcher.shared.store(full)
            }
            self.similar = await similar?.items ?? []
        }
    }

    func loadEpisodes(client: JellyfinClient) async {
        guard let season = selectedSeason else { return }
        episodes = (try? await client.episodes(seriesId: item.id, seasonId: season).items) ?? []
        if let selectedEpisode, episodes.contains(where: { $0.id == selectedEpisode.id }) { return }
        selectedEpisode = episodes.first { $0.id == nextUp?.id } ?? episodes.first { !$0.isPlayed } ?? episodes.first
    }

    /// What the big button plays: the item itself, or for a series the next
    /// unwatched episode.
    var playTarget: BaseItem? {
        item.kind == .series ? (selectedEpisode ?? nextUp ?? episodes.first) : (item.kind.isPlayable ? item : nil)
    }

    var badges: [String] {
        guard let source = item.mediaSources?.first else { return [] }
        var out: [String] = []
        if let v = source.videoStream {
            if (v.width ?? 0) >= 3800 { out.append("4K") } else if (v.height ?? 0) >= 1000 { out.append("HD") }
            if v.isDolbyVision { out.append("DOLBY VISION") }
            else if v.videoRangeType == "HDR10Plus" { out.append("HDR10+") }
            else if v.videoRange == "HDR" { out.append(v.videoRangeType == "HLG" ? "HLG" : "HDR10") }
        }
        if let a = source.audioStreams.first(where: { $0.isDefault == true }) ?? source.audioStreams.first {
            if a.isAtmos { out.append("DOLBY ATMOS") }
            else if (a.profile ?? "").contains("DTS:X") || a.audioSpatialFormat == "DTSX" { out.append("DTS:X") }
            if let ch = a.channels, ch > 2 { out.append(ch >= 8 ? "7.1" : ch >= 6 ? "5.1" : "\(ch)CH") }
        }
        if !source.subtitleStreams.isEmpty { out.append("CC") }
        return out
    }
}

struct ItemDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.castLink) private var castLink
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme
    @State private var model: DetailModel
    @State private var showTracks = false
    @FocusState private var playFocused: Bool

    init(item: BaseItem) { _model = State(initialValue: DetailModel(item: item)) }

    var body: some View {
        let item = model.item
        ZStack(alignment: .topLeading) {
            FocusBackdrop(item)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Layout.shelfSpacing) {
                    header(item)
                        .frame(minHeight: 760, alignment: .bottomLeading)
                        .padding(.horizontal, Layout.horizontalMargin)
                        .tvFocusSection()

                    if item.kind == .series && !model.seasons.isEmpty {
                        seasonPicker
                        Shelf("Episodes", items: model.episodes, style: .landscape) { ep in
                            LandscapeCard(ep, kind: .still) { app.play(ep) }
                                .contextMenu { ItemContextMenu(item: ep) }
                                .onFocused { model.selectedEpisode = ep }
                        }
                    }
                    if let people = item.people, !people.isEmpty {
                        CastShelf(people: Array(people.prefix(24)))
                    }
                    if !model.similar.isEmpty {
                        Shelf("More Like This", items: model.similar) { s in
                            PosterCard(s) { app.select(s, navigate: navigate) }
                                .contextMenu { ItemContextMenu(item: s) }
                        }
                    }
                }
                .padding(.bottom, 80)
            }
            .tvScrollClipDisabled()
        }
        // Land on Play: it's what the user came here to press. With a
        // sidebarAdaptable TabView the sidebar otherwise keeps focus on a
        // deep-linked page — and Menu from the sidebar exits the app.
        .defaultFocus($playFocused, true, priority: .userInitiated)
        // The companion shows the page you're on (again once its details arrive).
        .onAppear { app.focusedItem = model.item }
        .onChange(of: model.item) { _, item in app.focusedItem = item }
        .task {
            // Programmatic focus is ignored until the view has joined the focus
            // hierarchy (after the push transition), and how long that takes
            // varies — so request it until it actually lands, up to ~1 s.
            for _ in 0..<20 where !playFocused {
                playFocused = true
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let client = app.session?.client else { return }
            await model.load(client: client)
            // After load: the real item kind is known (a deep-linked stub isn't).
            if app.settings.playThemeMusic, model.item.kind != .movie || app.settings.themeMusicForMovies {
                Task { await ThemeMusic.shared.play(for: model.item, client: client, online: app.settings.onlineThemeFallback) }
            }
            if model.item.kind == .series { playFocused = true }   // button appears only after Next Up loads
        }
        .onDisappear {
            ThemeMusic.shared.stop(owner: model.item.seriesId ?? model.item.id)
            if app.playback == nil { app.releasePrepared() }      // left without playing
        }
        .sheet(isPresented: $showTracks) {
            TrackPicker(item: item)
        }
        .hidesNavigationBar()
    }

    @ViewBuilder
    private func header(_ item: BaseItem) -> some View {
        if item.kind == .series, let episode = model.selectedEpisode {
            seriesHeader(item, episode: episode)
        } else {
            itemHeader(item)
        }
    }

    /// Series page: show identity up top (small), then the selected episode.
    private func seriesHeader(_ series: BaseItem, episode: BaseItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if ArtworkSource.resolve(series, .logo) != nil {
                Artwork(item: series, kind: .logo, width: 440, contentMode: .fit)
                    .frame(width: 440, height: 130, alignment: .bottomLeading)
            } else {
                Text(series.name ?? "").font(.system(size: 52, weight: .bold)).foregroundStyle(theme.primaryText).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text([episode.episodeLabel, episode.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.title3.weight(.semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                MetadataLine(item: episodeMetadata(episode))
                Text(episode.overview(hidingSpoilers: app.settings.hideSpoilers) ?? (episode.isSpoilerSensitive && app.settings.hideSpoilers ? "Hidden until you've watched it." : ""))
                    .font(.callout).foregroundStyle(theme.secondaryText).lineLimit(3)
                    .frame(maxWidth: 1100, minHeight: 90, alignment: .topLeading)   // fixed height: focus moves don't shift the buttons
            }
            .id(episode.id)
            .transition(.opacity)
            actionButtons(series)
        }
        .animation(.easeOut(duration: 0.15), value: episode.id)
    }

    /// The episode line already names the episode; drop it from metadata.
    private func episodeMetadata(_ episode: BaseItem) -> BaseItem {
        var copy = episode
        copy.kind = .movie
        copy.genres = nil
        return copy
    }

    @ViewBuilder
    private func itemHeader(_ item: BaseItem) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if item.kind == .episode, let series = item.seriesName {
                Text(series).font(.title3).foregroundStyle(theme.secondaryText)
            }
            if ArtworkSource.resolve(item, .logo) != nil && item.kind != .episode {
                Artwork(item: item, kind: .logo, width: 640, contentMode: .fit)
                    .frame(width: 640, height: 200, alignment: .bottomLeading)
            } else {
                Text(item.name ?? "").font(.system(size: 72, weight: .bold)).foregroundStyle(theme.primaryText).lineLimit(2)
            }
            MetadataLine(item: item)
            if !model.badges.isEmpty {
                HStack(spacing: 10) { ForEach(model.badges, id: \.self) { Badge($0) } }
            }
            if let tagline = item.taglines?.first {
                Text(tagline).font(.headline).foregroundStyle(theme.primaryText)
            }
            if let overview = item.overview(hidingSpoilers: app.settings.hideSpoilers) {
                Text(overview).font(.callout).foregroundStyle(theme.secondaryText).lineLimit(4).frame(maxWidth: 1100, alignment: .leading)
            }
            actionButtons(item)
        }
    }

    @ViewBuilder
    private func actionButtons(_ item: BaseItem) -> some View {
        if Layout.device == .phone {
            // More buttons than a phone is wide: they scroll sideways.
            ScrollView(.horizontal, showsIndicators: false) { actionRow(item) }
                .scrollClipDisabled()
        } else {
            actionRow(item)
        }
    }

    private func actionRow(_ item: BaseItem) -> some View {
        HStack(spacing: Layout.device == .phone ? 18 : 22) {
            if let target = model.playTarget {
                Pill(playLabel(target), systemImage: "play.fill", prominent: true) { app.play(target) }
                    .pillCaption(target.resumePosition != nil ? "Resume" : "Play")
                    .focused($playFocused)
                    .onChange(of: playFocused) { _, focused in if focused { app.prepare(target) } }
                if let cast = castLink, let tv = cast.connectedTo {
                    Pill("Play on \(tv)", systemImage: "tv") { cast.play(target.id) }
                        .pillCaption("On TV")
                        .accessibilityIdentifier("detail.playOnTV")
                }
                if target.resumePosition != nil {
                    Pill("Play from Beginning", systemImage: "gobackward") { app.play(target, resume: false) }
                        .pillCaption("Restart")
                }
                Pill(app.queue.contains(target.id) ? "In Queue" : "Add to Queue", systemImage: app.queue.contains(target.id) ? "text.badge.checkmark" : "text.badge.plus",
                     active: app.queue.contains(target.id)) { app.queue.toggle(target) }
                    .pillCaption("Queue")
                    .accessibilityIdentifier("detail.queue")
                if item.kind == .series || item.kind == .movie {
                    // On a loop, not marking anything watched (a show from a random episode).
                    Pill("Background Noise", systemImage: "infinity") { app.playInBackground(item) }
                        .pillCaption("Background")
                        .accessibilityIdentifier("detail.background")
                }
                if item.kind.isPlayable, item.mediaSources?.first.map({ $0.audioStreams.count > 1 || !$0.subtitleStreams.isEmpty }) == true {
                    Pill("Audio and Subtitles", systemImage: "captions.bubble") { showTracks = true }
                        .pillCaption("Audio")
                }
            }
            // Downloads (iPhone, iPad, Mac): a film or episode, or a show's season.
            if item.kind.isPlayable {
                DownloadPill(item: model.item)
            } else if item.kind == .series, let season = model.selectedSeason {
                SeasonDownloadPill(seriesId: item.id, seasonId: season,
                                   seasonName: model.seasons.first { $0.id == season }?.name ?? "Season", episodes: model.episodes)
            }
            Pill(model.item.isPlayed ? "Watched" : "Mark Watched", systemImage: model.item.isPlayed ? "checkmark.circle.fill" : "checkmark.circle",
                 active: model.item.isPlayed) { toggleWatched() }
                .pillCaption("Watched")
            Pill(model.item.isFavorite ? "Favourite" : "Add to Favourites", systemImage: model.item.isFavorite ? "heart.fill" : "heart",
                 active: model.item.isFavorite) { toggleFavorite() }
                .pillCaption("Favourite")
        }
        .padding(.top, 8)
        .environment(\.pillCaptions, true)                   // touch and the Mac: what each button does
    }

    private func playLabel(_ target: BaseItem) -> String {
        let prefix = target.resumePosition != nil ? "Resume" : "Play"
        if model.item.kind == .series, let label = target.episodeLabel { return "\(prefix) \(label)" }
        if let pos = target.resumePosition, let total = target.runtime {
            let left = Int((total - pos).components.seconds / 60)
            return "\(prefix) · \(left)m left"
        }
        return prefix
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                ForEach(model.seasons) { season in
                    Button(season.name ?? "Season") {
                        model.selectedSeason = season.id
                        guard let client = app.session?.client else { return }
                        Task { await model.loadEpisodes(client: client) }
                    }
                    .buttonStyle(.bordered)
                    .tint(model.selectedSeason == season.id ? theme.accent : nil)
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 12)
        }
        .tvScrollClipDisabled()
        .tvFocusSection()
    }

    private func toggleWatched() {
        guard let client = app.session?.client else { return }
        let new = !model.item.isPlayed
        model.item.userData = model.item.userData ?? UserItemData()
        model.item.userData?.played = new
        Task { try? await client.setPlayed(new, itemId: model.item.id) }
    }

    private func toggleFavorite() {
        guard let client = app.session?.client else { return }
        let new = !model.item.isFavorite
        model.item.userData = model.item.userData ?? UserItemData()
        model.item.userData?.isFavorite = new
        Task { try? await client.setFavorite(new, itemId: model.item.id) }
    }
}

struct CastShelf: View {
    let people: [Person]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cast & Crew").font(.headline).foregroundStyle(theme.secondaryText).padding(.horizontal, Layout.horizontalMargin)
            ScrollView(.horizontal) {
                LazyHStack(spacing: Layout.cardSpacing) {
                    ForEach(people) { person in PersonCard(person) {} }
                }
                .padding(.horizontal, Layout.horizontalMargin)
                .padding(.vertical, 28)
            }
            .tvScrollClipDisabled()
        }
        .tvFocusSection()
    }
}

/// Pre-play audio / subtitle / version selection.
struct TrackPicker: View {
    let item: BaseItem
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var audio: Int?
    @State private var subtitle: Int?

    var body: some View {
        let source = item.mediaSources?.first
        NavigationStack {
            List {
                Section("Audio") {
                    ForEach(source?.audioStreams ?? [], id: \.index) { s in
                        Button { audio = s.index } label: {
                            HStack { Text(s.displayTitle ?? s.codec ?? "Track \(s.index)"); Spacer(); if (audio ?? source?.defaultAudioStreamIndex) == s.index { Image(systemName: "checkmark") } }
                        }
                    }
                }
                Section("Subtitles") {
                    Button { subtitle = -1 } label: {
                        HStack { Text("Off"); Spacer(); if subtitle == -1 { Image(systemName: "checkmark") } }
                    }
                    ForEach(source?.subtitleStreams ?? [], id: \.index) { s in
                        Button { subtitle = s.index } label: {
                            HStack { Text(s.displayTitle ?? s.language ?? "Track \(s.index)"); Spacer(); if subtitle == s.index { Image(systemName: "checkmark") } }
                        }
                    }
                }
                Section {
                    Button("Play", systemImage: "play.fill") {
                        dismiss()
                        app.play(item, mediaSourceId: source?.id, audioIndex: audio, subtitleIndex: subtitle)
                    }
                }
            }
            .navigationTitle(item.name ?? "")
        }
    }
}
