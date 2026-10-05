import AppCore
import DesignSystem
import JellyfinAPI
import SwiftUI

// MARK: - Buttons on a detail page

/// A film's or an episode's Download button: Download → 42% (pauses) →
/// Paused (resumes) → Downloaded (offers removal).
struct DownloadPill: View {
    let item: BaseItem
    @Environment(AppModel.self) private var app
    @State private var confirmRemove = false

    var body: some View {
        if let store = app.downloads, let session = app.session {
            let record = store.record(item.id)
            Group {
                switch record?.state {
                case nil:
                    Pill("Download", systemImage: "arrow.down.circle") { start(store, session, app.defaultDownloadPreset) }
                        // Any other size: long-press (iPhone, iPad) or right-click (Mac).
                        .contextMenu {
                            ForEach(DownloadPreset.allCases) { preset in
                                Button("\(preset.title) · \(preset.perHour)") { start(store, session, preset) }
                            }
                        }
                case .queued?:
                    Pill("Waiting to Download", systemImage: "clock", active: true) { store.pause(item.id) }
                case .downloading?, .finishing?:
                    Pill(record?.progress.map { "Downloading \(Int($0 * 100))%" } ?? "Downloading", systemImage: "pause.circle", active: true) { store.pause(item.id) }
                case .paused?:
                    Pill(record?.progress.map { "Paused at \(Int($0 * 100))%" } ?? "Paused", systemImage: "arrow.down.circle") { store.resume(item.id) }
                case .failed?:
                    Pill("Download Again", systemImage: "exclamationmark.arrow.circlepath") { store.resume(item.id) }
                case .done?:
                    Pill("Downloaded", systemImage: "checkmark.circle.fill", active: true) { confirmRemove = true }
                }
            }
            .pillCaption(DownloadWords.caption(record))
            .accessibilityIdentifier("detail.download")
            .confirmationDialog("Remove the download?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove Download", role: .destructive) { store.remove([item.id]) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(item.name ?? "It") stays in your library; only this device's copy goes\(record?.size.map { " (\(DownloadWords.bytes($0)))" } ?? "").")
            }
        }
    }
}

extension DownloadPill {
    private func start(_ store: DownloadStore, _ session: UserSession, _ preset: DownloadPreset) {
        store.download([item], client: session.client, accountId: session.account.id, quality: preset.quality)
    }
}

/// A season's: Download Season → 3 of 10 → Season Downloaded (offers removal).
struct SeasonDownloadPill: View {
    let seriesId: String
    let seasonId: String?
    let seasonName: String
    let episodes: [BaseItem]
    @Environment(AppModel.self) private var app
    @State private var confirmRemove = false

    var body: some View {
        if let store = app.downloads, let session = app.session, !episodes.isEmpty {
            let summary = store.summary(seriesId: seriesId, seasonId: seasonId)
            Group {
                if summary.total >= episodes.count && summary.done == summary.total {
                    Pill("\(seasonName) Downloaded", systemImage: "checkmark.circle.fill", active: true) { confirmRemove = true }
                } else if summary.active > 0 {
                    Pill("Downloading \(summary.done) of \(summary.total)", systemImage: "arrow.down.circle", active: true) {}
                } else {
                    Pill("Download \(seasonName)", systemImage: "arrow.down.circle") {
                        store.download(episodes, client: session.client, accountId: session.account.id, quality: app.defaultDownloadPreset.quality)
                    }
                    .contextMenu {
                        ForEach(DownloadPreset.allCases) { preset in
                            Button("\(preset.title) · \(preset.perHour)") {
                                store.download(episodes, client: session.client, accountId: session.account.id, quality: preset.quality)
                            }
                        }
                    }
                }
            }
            .pillCaption("Season")
            .accessibilityIdentifier("detail.downloadSeason")
            .confirmationDialog("Remove \(seasonName)'s downloads?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove Downloads", role: .destructive) { store.removeSeries(seriesId, seasonId: seasonId) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

// MARK: - The Downloads page

/// Everything on this device: what's coming down, then films, then shows
/// (each opening its episodes). Works with no connection.
struct DownloadsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate
    @Environment(\.theme) private var theme
    @Environment(\.pageWidth) private var width

    var body: some View {
        let store = app.downloads
        let all = store.map { Array($0.records.values) } ?? []
        let active = all.filter { !$0.isDone }.sorted { $0.addedAt < $1.addedAt }
        let films = all.filter { $0.isDone && $0.item.seriesId == nil }.sorted { ($0.item.name ?? "") < ($1.item.name ?? "") }
        let shows = Dictionary(grouping: all.filter { $0.isDone && $0.item.seriesId != nil }, by: { $0.item.seriesId! })
            .values.sorted { ($0.first?.item.seriesName ?? "") < ($1.first?.item.seriesName ?? "") }
        let columns = Layout.columns(width, minWidth: Layout.landscapeMin, max: 4)
        let cardWidth = Layout.cardWidth(width, columns: columns)
        let grid = Array(repeating: GridItem(.fixed(cardWidth), spacing: Layout.cardSpacing, alignment: .top), count: columns)
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Downloads").font(.system(size: Layout.pageTitleSmall, weight: .bold)).foregroundStyle(theme.primaryText)
                    Text(DownloadWords.lede(films: films.count, episodes: shows.reduce(0) { $0 + $1.count }, used: store?.bytesUsed ?? 0, free: store?.freeBytes))
                        .font(.title3).foregroundStyle(theme.secondaryText)
                }
                .padding(.top, Layout.device == .phone ? PillSize.regular.diameter + 8 : 0)
                if all.isEmpty {
                    Text("Download a film or an episode from its page, and it plays from here with no connection.")
                        .font(.callout).foregroundStyle(theme.secondaryText)
                }
                if !active.isEmpty {
                    section("Downloading", subtitle: active.count == 1 ? "One on its way." : "\(active.count) on their way, one at a time.") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(active) { DownloadRow(record: $0) }
                        }
                    }
                }
                if !films.isEmpty {
                    section("Films", subtitle: DownloadWords.count(films.count, "film", "films") + ", " + DownloadWords.bytes(films.reduce(0) { $0 + ($1.size ?? 0) }) + ".") {
                        LazyVGrid(columns: grid, alignment: .leading, spacing: Layout.shelfSpacing) {
                            ForEach(films) { r in
                                LandscapeCard(r.item, width: cardWidth) { app.play(r.item) }
                                    .contextMenu { Button("Remove Download", systemImage: "trash", role: .destructive) { store?.remove([r.id]) } }
                                    .accessibilityIdentifier("downloads.film.\(r.id)")
                            }
                        }
                    }
                }
                if !shows.isEmpty {
                    section("Shows", subtitle: DownloadWords.count(shows.count, "show", "shows") + ".") {
                        LazyVGrid(columns: grid, alignment: .leading, spacing: Layout.shelfSpacing) {
                            ForEach(shows, id: \.first!.item.seriesId) { episodes in
                                let first = episodes[0]
                                ShowTile(record: first, count: episodes.count, bytes: episodes.reduce(0) { $0 + ($1.size ?? 0) }, width: cardWidth) {
                                    navigate(.downloadedShow(first.item.seriesId!))
                                }
                                .contextMenu { Button("Remove All Episodes", systemImage: "trash", role: .destructive) { store?.removeSeries(first.item.seriesId!) } }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 40)
        }
        .tvScrollClipDisabled()
        .background(theme.backgroundGradient.ignoresSafeArea())
        .hidesNavigationBar()
    }

    private func section<C: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title3.weight(.bold)).foregroundStyle(theme.primaryText)
                Text(subtitle).font(.callout).foregroundStyle(theme.secondaryText)
            }
            content()
        }
    }
}

/// A download on its way: title, progress, pause/resume, remove.
private struct DownloadRow: View {
    let record: DownloadRecord
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        let store = app.downloads
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(DownloadWords.title(record.item)).font(.callout.weight(.semibold)).foregroundStyle(theme.primaryText).lineLimit(1)
                Text(DownloadWords.status(record)).font(.caption).foregroundStyle(theme.secondaryText).lineLimit(1)
                ProgressStrip(record.progress ?? 0).frame(maxWidth: 420)
            }
            Spacer(minLength: 12)
            switch record.state {
            case .paused, .failed:
                Pill("Resume", systemImage: "arrow.down.circle", size: .small) { store?.resume(record.id) }
            default:
                Pill("Pause", systemImage: "pause", size: .small) { store?.pause(record.id) }
            }
            Pill("Remove", systemImage: "xmark", size: .small) { store?.remove([record.id]) }
        }
        .padding(16)
        .background(theme.surface, in: .rect(cornerRadius: 18))
        .accessibilityIdentifier("downloads.active.\(record.id)")
    }
}

/// A show on the Downloads page: its art, how many episodes, how much space.
private struct ShowTile: View {
    let record: DownloadRecord
    let count: Int
    let bytes: Int64
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        var show = record.item
        show.id = record.item.seriesId ?? record.item.id
        show.name = record.item.seriesName ?? record.item.name
        show.kind = .series
        show.productionYear = nil
        return LandscapeCard(show, width: width, kind: .landscape, action: action)
            .overlay(alignment: .bottomLeading) {
                Text("\(DownloadWords.count(count, "episode", "episodes")) · \(DownloadWords.bytes(bytes))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .offset(y: 22)
            }
            .padding(.bottom, 22)
            .accessibilityIdentifier("downloads.show.\(show.id)")
    }
}

/// One show's downloaded episodes, by season, each removable — and the
/// whole season or show at once.
struct DownloadedShowView: View {
    let seriesId: String
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.pageWidth) private var width
    @State private var confirmRemoveAll = false

    var body: some View {
        let store = app.downloads
        let episodes = store?.episodes(seriesId: seriesId) ?? []
        let seasons = Dictionary(grouping: episodes, by: { $0.item.parentIndexNumber ?? 0 }).sorted { $0.key < $1.key }
        let columns = Layout.columns(width, minWidth: Layout.landscapeMin, max: 4)
        let cardWidth = Layout.cardWidth(width, columns: columns)
        let grid = Array(repeating: GridItem(.fixed(cardWidth), spacing: Layout.cardSpacing, alignment: .top), count: columns)
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(episodes.first?.item.seriesName ?? "Show").font(.system(size: Layout.pageTitleSmall, weight: .bold)).foregroundStyle(theme.primaryText)
                        Text("\(DownloadWords.count(episodes.count, "episode", "episodes")) on this device, \(DownloadWords.bytes(episodes.reduce(0) { $0 + ($1.size ?? 0) })).")
                            .font(.title3).foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    if !episodes.isEmpty {
                        Pill("Remove All", systemImage: "trash", size: .small, alwaysShowsTitle: true) { confirmRemoveAll = true }
                            .accessibilityIdentifier("downloads.removeShow")
                    }
                }
                ForEach(seasons, id: \.key) { season, eps in
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(season == 0 ? "Specials" : "Season \(season)").font(.title3.weight(.bold)).foregroundStyle(theme.primaryText)
                            Spacer()
                            Pill("Remove Season", systemImage: "trash", size: .small) { store?.remove(eps.map(\.id)) }
                        }
                        LazyVGrid(columns: grid, alignment: .leading, spacing: Layout.shelfSpacing) {
                            ForEach(eps) { r in
                                LandscapeCard(r.item, width: cardWidth, kind: .still) { app.play(r.item) }
                                    .contextMenu { Button("Remove Download", systemImage: "trash", role: .destructive) { store?.remove([r.id]) } }
                                    .accessibilityIdentifier("downloads.episode.\(r.id)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 40)
        }
        .tvScrollClipDisabled()
        .background(theme.backgroundGradient.ignoresSafeArea())
        .hidesNavigationBar()
        .confirmationDialog("Remove every downloaded episode?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) { store?.removeSeries(seriesId) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Words

enum DownloadWords {
    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    /// A Download button's caption: "Download", "42%", "Paused", "Downloaded".
    static func caption(_ r: DownloadRecord?) -> String {
        switch r?.state {
        case nil: "Download"
        case .queued?: "Waiting"
        case .downloading?, .finishing?: r?.progress.map { "\(Int($0 * 100))%" } ?? "Downloading"
        case .paused?: "Paused"
        case .failed?: "Retry"
        case .done?: "Downloaded"
        }
    }

    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
        return "\(n < words.count ? words[n] : String(n)) \(n == 1 ? one : many)"
    }

    static var device: String {
        switch Layout.device {
        case .phone: "iPhone"
        case .pad: "iPad"
        default: Platform.isMac ? "Mac" : "device"
        }
    }

    /// "Three films and twelve episodes, 48.2 GB. 210 GB free on this iPhone."
    static func lede(films: Int, episodes: Int, used: Int64, free: Int64?) -> String {
        let freeText = free.map { " \(bytes($0)) free on this \(device)." } ?? ""
        guard films + episodes > 0 else { return "Nothing here yet.\(freeText)" }
        let parts = [films > 0 ? count(films, "film", "films").lowercased() : nil, episodes > 0 ? count(episodes, "episode", "episodes").lowercased() : nil].compactMap { $0 }
        return (parts.joined(separator: " and ").prefix(1).uppercased() + parts.joined(separator: " and ").dropFirst()) + ", \(bytes(used)).\(freeText)"
    }

    static func title(_ item: BaseItem) -> String {
        if let series = item.seriesName { return "\(series) · \(item.episodeLabel ?? "") \(item.name ?? "")".trimmingCharacters(in: .whitespaces) }
        return item.name ?? "Untitled"
    }

    static func status(_ r: DownloadRecord) -> String {
        let done = bytes(r.received), total = r.size.map(bytes)
        switch r.state {
        case .queued: return "Waiting its turn."
        case .downloading: return total.map { "\(done) of \($0)" } ?? done
        case .finishing: return "Almost there."
        case .paused: return "Paused at \(done)" + (total.map { " of \($0)" } ?? "") + "."
        case .failed(let message): return "Stopped: \(message)"
        case .done: return "Downloaded."
        }
    }
}
