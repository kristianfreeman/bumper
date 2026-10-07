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
            // A deep link (or the Top Shelf) opens a stub of unknown kind:
            // the full item says whether it's a show.
            let knownSeries = item.kind == .series
            if knownSeries { await loadSeries(client: client) }
            if let full = await full {
                item = full
                DetailPrefetcher.shared.store(full)
            }
            if !knownSeries && item.kind == .series { await loadSeries(client: client) }
            // An episode opens in its show: that season, that episode in the
            // header — not a page of its own, out of context.
            if item.kind == .episode, let seriesId = item.seriesId, let series = try? await client.item(id: seriesId) {
                let episode = item
                TraceFile.write("detail", "episode \(episode.id) opens in \(seriesId), season \(episode.seasonId ?? "?")")
                selectedSeason = episode.seasonId
                selectedEpisode = episode
                item = series
                await loadSeries(client: client)
            }
            self.similar = await similar?.items ?? []
        }
    }

    private func loadSeries(client: JellyfinClient) async {
        async let seasons = try? client.seasons(seriesId: item.id)
        async let next = try? client.nextUp(limit: 1, seriesId: item.id)
        self.seasons = await seasons?.items ?? []
        nextUp = await next?.items.first
        if selectedSeason == nil { selectedSeason = nextUp?.seasonId ?? self.seasons.first?.id }
        await loadEpisodes(client: client)
    }

    /// Every season's episodes, in one row: the season bar follows along.
    func loadEpisodes(client: JellyfinClient) async {
        episodes = (try? await client.episodes(seriesId: item.id, seasonId: nil).items) ?? []
        if let selectedEpisode, episodes.contains(where: { $0.id == selectedEpisode.id }) { return }
        let inSeason = episodes.filter { $0.seasonId == selectedSeason }
        selectedEpisode = episodes.first { $0.id == nextUp?.id } ?? inSeason.first { !$0.isPlayed } ?? inSeason.first ?? episodes.first
        if let season = selectedEpisode?.seasonId { selectedSeason = season }
    }

    func episodes(in season: String) -> [BaseItem] { episodes.filter { $0.seasonId == season } }

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
    /// Which of the other actions has focus: the row animates as one when a
    /// pill opens to show its name (each pill only animates itself, and its
    /// neighbours jumped aside in a single frame).
    @FocusState private var actionFocus: String?
    /// The episode row's scroll position (a season picked jumps it).
    @State private var episodeScroll: String?
    /// A season jumped to: the row passing other seasons on its way doesn't move the bar.
    @State private var jumping: String?

    init(item: BaseItem) { _model = State(initialValue: DetailModel(item: item)) }

    /// How tall the header is at least, its content at the bottom: on the
    /// TV, Mac and iPad over the page's backdrop; an iPhone has the backdrop
    /// as a band above it instead (`DetailHero`), and no room to spare.
    private static let headerHeight: CGFloat = switch Layout.device { case .tv: 760; case .mac: 480; case .pad: 560; case .phone: 0 }
    private static var phone: Bool { Layout.device == .phone }

    var body: some View {
        // A stub of unknown kind (a deep link) that turns out to be a playlist.
        if model.item.kind == .playlist { PlaylistPage(playlist: model.item) } else { details }
    }

    private var details: some View {
        let item = model.item
        return ZStack(alignment: .topLeading) {
            if Self.phone { theme.backgroundGradient.ignoresSafeArea() } else { FocusBackdrop(item) }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Layout.shelfSpacing) {
                    VStack(alignment: .leading, spacing: 0) {
                        if Self.phone { DetailHero(item: item).padding(.bottom, -72) }    // the title sits on the art's fade
                        header(item)
                            .frame(minHeight: Self.headerHeight, alignment: .bottomLeading)
                            .padding(.horizontal, Layout.horizontalMargin)
                    }
                    .tvFocusSection()

                    if item.kind == .series && !model.seasons.isEmpty {
                        episodesRow
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
            .ignoresSafeArea(.container, edges: Self.phone ? .top : [])      // the art runs up under the status bar
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
        VStack(alignment: .leading, spacing: Self.phone ? 12 : 18) {
            TitleArt(item: series, small: true)
            VStack(alignment: .leading, spacing: 10) {
                Text([episode.episodeLabel, episode.name].compactMap { $0 }.joined(separator: " · "))
                    .font(Self.phone ? .headline : .title3.weight(.semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                MetadataLine(item: episodeMetadata(episode))
                Text(episode.overview ?? "")
                    .font(.detailText).foregroundStyle(theme.secondaryText).lineLimit(3)
                    .spoilerBlur(episode.spoils(hidingSpoilers: app.settings.hideSpoilers), revealable: true)
                    .frame(maxWidth: 1100, minHeight: Self.phone ? 0 : 90, alignment: .topLeading)   // fixed height: focus moves don't shift the buttons
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
        VStack(alignment: .leading, spacing: Self.phone ? 12 : 22) {
            if item.kind == .episode, let series = item.seriesName {
                Text(series).font(.title3).foregroundStyle(theme.secondaryText)
            }
            TitleArt(item: item, small: false)
            MetadataLine(item: item)
            if !model.badges.isEmpty {
                HStack(spacing: 10) { ForEach(model.badges, id: \.self) { Badge($0) } }
            }
            if let tagline = item.taglines?.first {
                Text(tagline).font(.headline).foregroundStyle(theme.primaryText)
            }
            if let overview = item.overview {
                Text(overview).font(.detailText).foregroundStyle(theme.secondaryText).lineLimit(Self.phone ? 3 : 4).frame(maxWidth: 1100, alignment: .leading)
                    .spoilerBlur(item.spoils(hidingSpoilers: app.settings.hideSpoilers), revealable: true)
            }
            actionButtons(item)
        }
    }

    /// Play first and biggest (on an iPhone a full-width button); then the
    /// few things done most — Restart, Queue, Background, Download — and
    /// the rest (Watched, Favourite, Audio and Subtitles) in More.
    @ViewBuilder
    private func actionButtons(_ item: BaseItem) -> some View {
        if Self.phone {
            VStack(alignment: .leading, spacing: 16) {
                if let target = model.playTarget { WidePlayButton(title: playLabel(target), target: target, focus: $playFocused) }
                // Bigger than the TV's, scaled: in a row that scrolls sideways if it has to.
                ScrollView(.horizontal, showsIndicators: false) { secondaryRow(item, size: .large) }
                    .scrollClipDisabled()
            }
            .padding(.top, 6)
            .environment(\.pillCaptions, true)
        } else {
            HStack(spacing: 22) {
                if let target = model.playTarget {
                    Pill(playLabel(target), systemImage: castLink?.isConnected == true ? "play.tv.fill" : "play.fill", prominent: true) { app.play(target) }
                        .pillCaption(castLink?.connectedTo.map { "On \($0)" } ?? (target.resumePosition != nil ? "Resume" : "Play"))
                        .focused($playFocused)
                        .onChange(of: playFocused) { _, focused in if focused { app.prepare(target) } }
                        .accessibilityIdentifier("detail.play")
                }
                secondaryRow(item, size: .regular)
            }
            .animation(.spring(duration: 0.3, bounce: 0.2), value: actionFocus)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: playFocused)
            .padding(.top, 8)
            .environment(\.pillCaptions, true)                   // touch and the Mac: what each button does
        }
    }

    private func secondaryRow(_ item: BaseItem, size: PillSize) -> some View {
        HStack(spacing: Self.phone ? 16 : 22) {
            if let target = model.playTarget {
                if target.resumePosition != nil {
                    Pill("Play from Beginning", systemImage: "gobackward", size: size) { app.play(target, resume: false) }
                        .pillCaption("Restart")
                        .focused($actionFocus, equals: "restart")
                }
                Pill(app.queue.contains(target.id) ? "In Queue" : "Add to Queue", systemImage: app.queue.contains(target.id) ? "text.badge.checkmark" : "text.badge.plus",
                     size: size, active: app.queue.contains(target.id)) { app.toggleQueue(target) }
                    .pillCaption("Queue")
                    .focused($actionFocus, equals: "queue")
                    .accessibilityIdentifier("detail.queue")
                if item.kind == .series || item.kind == .movie {
                    // On a loop, not marking anything watched (a show from a random episode).
                    Pill("Untracked", systemImage: "infinity", size: size) { app.playInBackground(item) }
                        .focused($actionFocus, equals: "background")
                        .accessibilityIdentifier("detail.background")
                }
            }
            // Downloads (iPhone, iPad, Mac): a film or episode, or a show's season.
            if item.kind.isPlayable {
                DownloadPill(item: model.item, size: size)
                    .focused($actionFocus, equals: "download")
            } else if item.kind == .series, let season = model.selectedSeason {
                SeasonDownloadPill(seriesId: item.id, seasonId: season,
                                   seasonName: model.seasons.first { $0.id == season }?.name ?? "Season", episodes: model.episodes(in: season), size: size)
                    .focused($actionFocus, equals: "download")
            }
            moreMenu(item, size: size)
        }
    }

    /// Watched, Favourite, and the tracks to start with.
    private func moreMenu(_ item: BaseItem, size: PillSize) -> some View {
        Menu {
            Button(model.item.isPlayed ? "Mark Unwatched" : "Mark Watched", systemImage: model.item.isPlayed ? "checkmark.circle.fill" : "checkmark.circle") { toggleWatched() }
                .accessibilityIdentifier("detail.watched")
            Button(model.item.isFavorite ? "Remove from Favourites" : "Add to Favourites", systemImage: model.item.isFavorite ? "heart.fill" : "heart") { toggleFavorite() }
                .accessibilityIdentifier("detail.favourite")
            if item.kind.isPlayable, item.mediaSources?.first.map({ $0.audioStreams.count > 1 || !$0.subtitleStreams.isEmpty }) == true {
                Button("Audio and Subtitles…", systemImage: "captions.bubble") { showTracks = true }
            }
        } label: {
            PillFace("More", size: size, active: model.item.isPlayed || model.item.isFavorite) { PillSymbol("ellipsis", size: size) }
                .pillCaption("More")
        }
        .buttonStyle(PillButtonStyle())
        .menuIndicator(.hidden)
        .focused($actionFocus, equals: "more")
        .accessibilityLabel("More")
        .accessibilityIdentifier("detail.more")
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

    /// The season bar (like the top nav) over one row of every episode:
    /// moving along the row moves the bar; picking a season jumps the row.
    private var episodesRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            SeasonBar(seasons: model.seasons, selected: model.selectedSeason) { season in
                model.selectedSeason = season.id
                if let first = model.episodes(in: season.id).first {
                    jumping = season.id
                    withAnimation(.smooth(duration: 0.4)) { episodeScroll = first.id }
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Layout.cardSpacing) {
                    ForEach(model.episodes) { ep in
                        LandscapeCard(ep, kind: .still) { app.play(ep) }
                            .contextMenu { ItemContextMenu(item: ep) }
                            .onFocused {
                                model.selectedEpisode = ep
                                if let season = ep.seasonId, season != model.selectedSeason { model.selectedSeason = season }
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 28)
            }
            .contentMargins(.horizontal, Layout.horizontalMargin, for: .scrollContent)   // a jump lands inside the margin
            .scrollPosition(id: $episodeScroll, anchor: .leading)
            .scrollIndicators(.hidden)
            .tvScrollClipDisabled()
            // Touch and the Mac: the first episode in view says which season
            // you're in (the TV says it by focus). A jump's passing seasons don't.
            .onScrollTargetVisibilityChange(idType: BaseItem.ID.self, threshold: 0.6) { visible in
                guard !Platform.isTV, let first = visible.first, let ep = model.episodes.first(where: { $0.id == first }), let season = ep.seasonId else { return }
                if let target = jumping { if season == target { jumping = nil }; return }
                if season != model.selectedSeason { model.selectedSeason = season }
            }
            .onChange(of: model.episodes.map(\.id)) { _, _ in episodeScroll = model.selectedEpisode?.id }
            .tvFocusSection()
        }
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

/// The title as the show's logo where there is one, else in type — sized
/// to the page: never wider than it, so nothing lays out past the screen's
/// edge while the image arrives.
private struct TitleArt: View {
    let item: BaseItem
    /// A series page's: smaller, above the episode it describes.
    let small: Bool
    @Environment(\.pageWidth) private var pageWidth
    @Environment(\.theme) private var theme

    private var box: CGSize {
        let tv = small ? CGSize(width: 440, height: 130) : CGSize(width: 640, height: 200)
        let scale: CGFloat = switch Layout.device { case .tv: 1; case .mac: 0.7; case .pad: 0.75; case .phone: 0.55 }
        let width = min((tv.width * scale).rounded(), (pageWidth * 0.8).rounded())
        return CGSize(width: width, height: (tv.height * scale).rounded())
    }

    private var fontSize: CGFloat {
        let tv: CGFloat = small ? 52 : 72
        return switch Layout.device { case .tv: tv; case .mac: tv * 0.62; case .pad: tv * 0.66; case .phone: small ? 24 : 30 }
    }

    var body: some View {
        if ArtworkSource.resolve(item, .logo) != nil && item.kind != .episode {
            Artwork(item: item, kind: .logo, width: box.width, contentMode: .fit)
                .frame(width: box.width, height: box.height, alignment: .bottomLeading)
        } else {
            Text(item.name ?? "")
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(small ? 1 : 2)
                .minimumScaleFactor(0.8)
        }
    }
}

/// An iPhone's backdrop: a band of the art across the top (under the
/// status bar) that fades into the page, instead of the whole screen.
private struct DetailHero: View {
    let item: BaseItem
    @Environment(\.pageWidth) private var pageWidth
    @Environment(\.theme) private var theme

    var body: some View {
        let width = pageWidth + 2 * Layout.horizontalMargin
        let height = (width * 0.8).rounded()
        Artwork(item: item, kind: .backdrop, width: width)
            .frame(width: width, height: height)
            .clipped()
            .overlay {
                LinearGradient(stops: [
                    .init(color: theme.backgroundTop.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: theme.backgroundTop.opacity(0.6), location: 0.62),
                    .init(color: theme.backgroundTop, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
    }
}

/// An iPhone's Play: the width of the page, and what it'll do —
/// "Resume · 42m left", or, connected to a TV, on which TV.
private struct WidePlayButton: View {
    let title: String
    let target: BaseItem
    var focus: FocusState<Bool>.Binding
    @Environment(AppModel.self) private var app
    @Environment(\.castLink) private var cast
    @Environment(\.theme) private var theme

    var body: some View {
        let tv = cast?.connectedTo
        VStack(alignment: .leading, spacing: 8) {
            Button { app.play(target) } label: {
                HStack(spacing: 10) {
                    Image(systemName: tv == nil ? "play.fill" : "play.tv.fill")
                    Text(tv.map { "\(title) on \($0)" } ?? title).lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.headline)
                .foregroundStyle(theme.colorScheme == .light ? .white : .black)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(theme.accent, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(PillButtonStyle())
            .focused(focus)
            .accessibilityIdentifier("detail.play")
            // This one, playing on the TV right now.
            if let playing = cast?.nowPlaying, playing.itemId == target.id, let on = cast?.watching {
                Label("\(playing.paused ? "Paused" : "Playing") on \(on) · \(CastLink.clock(playing.position)) of \(CastLink.clock(playing.duration))",
                      systemImage: "tv")
                    .font(.smallText.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("detail.onTV")
            }
        }
    }
}

/// The seasons, as the top nav shows its tabs: the season you're in lit,
/// focus (the TV) white.
struct SeasonBar: View {
    let seasons: [BaseItem]
    let selected: String?
    let pick: (BaseItem) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Platform.isTV ? 6 : 2) {
                ForEach(seasons) { season in
                    Button { pick(season) } label: { SeasonTab(title: season.name ?? "Season", selected: selected == season.id) }
                        .buttonStyle(PillButtonStyle())
                        .accessibilityIdentifier("season.\(season.indexNumber ?? 0)")
                        .accessibilityAddTraits(selected == season.id ? .isSelected : [])
                }
            }
            .padding(Platform.isTV ? 8 : 4)
            .background(theme.primaryText.opacity(0.08), in: .capsule)
            .padding(.vertical, Platform.isTV ? 12 : 4)
        }
        .scrollIndicators(.hidden)
        .tvScrollClipDisabled()
        .tvFocusSection()
        .animation(.spring(duration: 0.3, bounce: 0.12), value: selected)
    }
}

private struct SeasonTab: View {
    let title: String
    let selected: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(Platform.isTV ? .callout.weight(.semibold) : .subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, Platform.isTV ? 28 : 14)
            .padding(.vertical, Platform.isTV ? 12 : 7)
            .foregroundStyle(focused ? Color.black : selected ? theme.primaryText : theme.secondaryText)
            .background {
                if focused { Capsule().fill(.white) } else if selected { Capsule().fill(theme.primaryText.opacity(0.16)) }
            }
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.15), value: focused)
            .contentShape(.capsule)
    }
}
