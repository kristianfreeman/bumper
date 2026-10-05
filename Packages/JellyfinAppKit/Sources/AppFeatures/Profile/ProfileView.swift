import AppCore
import DesignSystem
import Foundation
import JellyfinAPI
import Observation
import SwiftUI

// MARK: - Stats

nonisolated struct UserStats: Codable, Sendable {
    var moviesWatched = 0
    var episodesWatched = 0
    var showsStarted = 0
    var favorites = 0
    var inProgress = 0
    var hoursWatched = 0.0
    var topGenres: [GenreCount] = []

    struct GenreCount: Codable, Sendable, Hashable { var name: String; var count: Int }
}

@MainActor
@Observable
final class ProfileModel {
    private(set) var user: UserDto?
    private(set) var stats: UserStats?
    private(set) var server: PublicSystemInfo?

    func load(client: JellyfinClient) async {
        let key = "profile-stats-\(client.userId ?? "")"
        if stats == nil { stats = await ContentCache.shared.value(UserStats.self, for: key) }   // instant repaint
        async let user = try? client.currentUser()
        async let server = try? client.publicSystemInfo()
        async let fresh = Self.computeStats(client: client)
        self.user = await user
        self.server = await server
        let computed = await fresh
        stats = computed
        await ContentCache.shared.store(computed, for: key)
    }

    /// Counts are `limit=0` queries (the server counts, nothing is sent);
    /// hours and genres need the played items themselves, asked for with
    /// no images and only the fields used.
    nonisolated static func computeStats(client: JellyfinClient) async -> UserStats {
        func query(_ types: [ItemKind], _ filters: [String], limit: Int?, fields: [ItemField] = []) -> ItemQuery {
            var q = ItemQuery(includeItemTypes: types, limit: limit)
            q.filters = filters
            q.fields = fields
            q.imageTypes = []
            return q
        }
        async let movies = try? client.items(query([.movie], ["IsPlayed"], limit: 10_000, fields: [.genres]))
        async let episodes = try? client.items(query([.episode], ["IsPlayed"], limit: 50_000))
        async let favorites = try? client.items(query([.movie, .series, .episode], ["IsFavorite"], limit: 0))
        async let resumable = try? client.items(query([.movie, .episode], ["IsResumable"], limit: 0))
        async let series = try? client.items(query([.series], [], limit: 10_000, fields: [.genres]))

        let playedMovies = await movies?.items ?? []
        let playedEpisodes = await episodes?.items ?? []
        let started = Set(playedEpisodes.compactMap(\.seriesId))
        let startedSeries = (await series?.items ?? []).filter { started.contains($0.id) }

        var genres: [String: Int] = [:]
        for item in playedMovies + startedSeries { for g in item.genres ?? [] { genres[g, default: 0] += 1 } }
        let ticks = (playedMovies + playedEpisodes).reduce(Int64(0)) { $0 + ($1.runTimeTicks ?? 0) }

        return UserStats(
            moviesWatched: await movies?.totalRecordCount ?? playedMovies.count,
            episodesWatched: await episodes?.totalRecordCount ?? playedEpisodes.count,
            showsStarted: started.count,
            favorites: await favorites?.totalRecordCount ?? 0,
            inProgress: await resumable?.totalRecordCount ?? 0,
            hoursWatched: Double(ticks) / Double(BaseItem.ticksPerSecond) / 3600,
            topGenres: genres.sorted { $0.value > $1.value }.prefix(6).map { .init(name: $0.key, count: $0.value) }
        )
    }
}

// MARK: - Page

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var model = ProfileModel()

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            identity
                .frame(width: 520)
            ScrollView {
                VStack(alignment: .leading, spacing: 50) {
                    statGrid
                    genres
                    details
                }
                .padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .background(theme.backgroundGradient.ignoresSafeArea())
        .task {
            guard let client = app.session?.client else { return }
            await model.load(client: client)
        }
    }

    private var identity: some View {
        VStack(spacing: 24) {
            UserAvatar(size: 260)
            Text(model.user?.name ?? app.session?.account.userName ?? "")
                .font(.system(size: 52, weight: .bold)).foregroundStyle(theme.primaryText)
            if model.user?.policy?.isAdministrator == true {
                Text("Administrator").font(.caption.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(theme.accent.opacity(0.2), in: .capsule)
                    .foregroundStyle(theme.accent)
            }
            if let active = model.user?.lastActivityDate {
                Text("Last active \(active.formatted(.relative(presentation: .named)))")
                    .font(.callout).foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 40)
    }

    private var statGrid: some View {
        let s = model.stats
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 3), spacing: 32) {
            StatTile(symbol: "film", value: s.map { "\($0.moviesWatched)" }, label: "Movies watched")
            StatTile(symbol: "tv", value: s.map { "\($0.episodesWatched)" }, label: "Episodes watched")
            StatTile(symbol: "clock", value: s.map { Self.hours($0.hoursWatched) }, label: "Watched")
            StatTile(symbol: "rectangle.stack", value: s.map { "\($0.showsStarted)" }, label: "Shows started")
            StatTile(symbol: "play.circle", value: s.map { "\($0.inProgress)" }, label: "In progress")
            StatTile(symbol: "heart", value: s.map { "\($0.favorites)" }, label: "Favorites")
        }
    }

    static func hours(_ h: Double) -> String {
        h >= 48 ? "\(Int((h / 24).rounded())) days" : "\(Int(h.rounded())) hours"
    }

    @ViewBuilder
    private var genres: some View {
        if let top = model.stats?.topGenres, let most = top.first?.count, most > 0 {
            VStack(alignment: .leading, spacing: 18) {
                Text("Favourite Genres").font(.title3.bold()).foregroundStyle(theme.primaryText)
                    .padding(.bottom, 4)
                ForEach(top, id: \.self) { g in
                    HStack(spacing: 20) {
                        Text(g.name).font(.callout).foregroundStyle(theme.primaryText).frame(width: 220, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(theme.accent.opacity(0.85))
                                .frame(width: max(12, geo.size.width * CGFloat(g.count) / CGFloat(most)))
                        }
                        .frame(height: 14)
                        Text("\(g.count)").font(.callout.monospacedDigit()).foregroundStyle(theme.secondaryText).frame(width: 60, alignment: .trailing)
                    }
                }
            }
            .padding(28)
            .focusTile()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Server & Device").font(.title3.bold()).foregroundStyle(theme.primaryText)
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 12) {
                if let session = app.session {
                    row("Server", model.server?.serverName ?? session.server.name)
                    row("Jellyfin", model.server?.version ?? session.server.version ?? "–")
                    row("Address", session.server.url.host() ?? session.server.url.absoluteString)
                }
                row("Apple TV", PerfRecorder.hardwareModel)
                row("App", "\(Brand.displayName) \(Brand.version) (\(Brand.build))")
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .focusTile()
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(theme.secondaryText)
            Text(value).foregroundStyle(theme.primaryText)
        }
    }
}

struct StatTile: View {
    let symbol: String
    let value: String?
    let label: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(theme.accent)
            Text(value ?? "–").font(.system(size: 54, weight: .bold).monospacedDigit()).foregroundStyle(theme.primaryText)
                .contentTransition(.numericText())
            Text(label).font(.callout).foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .animation(.easeOut(duration: 0.3), value: value)
        .focusTile()
    }
}

/// tvOS only scrolls to what can take focus: info cards on a stats page are
/// focusable, with a gentle lift, so the remote can move down the page.
struct FocusTile: ViewModifier {
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .background(theme.surface.opacity(focused ? 1 : 0.7), in: .rect(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(theme.accent.opacity(focused ? 0.8 : 0), lineWidth: 3))
            .scaleEffect(focused ? 1.03 : 1)
            .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 18, y: 8)
            .focusable()
            .focused($focused)
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}

extension View {
    func focusTile() -> some View { modifier(FocusTile()) }
}

/// The signed-in user's Jellyfin picture, or their monogram.
struct UserAvatar: View {
    let size: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var scale

    var body: some View {
        let account = app.session?.account
        ZStack {
            Monogram(account?.userName ?? "?", size: size)
            if let account, let tag = account.imageTag, let client = app.session?.client {
                RemoteImage(request: ImageRequest(url: client.userImageURL(userId: account.userId, tag: tag, size: Int(size * scale)), maxPixelSize: Int(size * scale)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }

}

/// Minimal async image through the shared pipeline (memory/disk cached).
struct RemoteImage: View {
    let request: ImageRequest
    @State private var image: CGImage?

    var body: some View {
        // A real base view: modifiers on an empty Group never run, so the
        // load task never started.
        Color.clear
            .overlay {
                if let image = image ?? ImagePipeline.shared.cachedImage(for: request) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .task(id: request) {
            if ImagePipeline.shared.cachedImage(for: request) == nil {
                image = try? await ImagePipeline.shared.image(for: request)
            }
        }
    }
}
