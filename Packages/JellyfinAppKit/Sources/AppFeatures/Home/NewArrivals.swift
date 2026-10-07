import AppCore
import DesignSystem
import Foundation
import JellyfinAPI
import SwiftUI

/// What's new, named by what it is: shows you have with new episodes, shows
/// new to the library, films new to it. Home's rows and the pages behind
/// their "View all" use the same names, groupings and card labels.
nonisolated enum ArrivalKind: String, Codable, Sendable, Hashable {
    case episodes, shows, movies

    var title: String {
        switch self {
        case .episodes: "New Episodes"
        case .shows: "New Shows"
        case .movies: "New Movies"
        }
    }
}

/// One card: a show (with how many new episodes) or a film.
nonisolated struct Arrival: Codable, Sendable, Equatable, Identifiable {
    /// What the card shows: the show, or the film.
    var card: BaseItem
    /// The newest new episode, for a show with new episodes: opening the card
    /// opens the show at its season.
    var episode: BaseItem?
    var added: Date
    var newEpisodes: Int?
    var id: String { card.id }
}

/// A "View all" page of new arrivals.
nonisolated struct ArrivalsSpec: Hashable, Codable, Sendable {
    var kind: ArrivalKind
    var libraryId: String
    var title: String
}

nonisolated enum Arrivals {
    /// A show added within this long counts as a new show, not a show with
    /// new episodes (its episodes arriving with it).
    static let newShowWindow: TimeInterval = 45 * 86_400

    static func fetch(_ kind: ArrivalKind, library: String, client: JellyfinClient, limit: Int) async throws -> [Arrival] {
        switch kind {
        case .movies, .shows:
            let items = try await client.items(query(kind == .movies ? .movie : .series, library: library, limit: limit)).items
            return items.map { Arrival(card: $0, added: $0.dateCreated ?? .distantPast) }
        case .episodes:
            async let shows = client.items(query(.series, library: library, limit: 60)).items
            let episodes = try await client.items(query(.episode, library: library, limit: min(500, limit * 8))).items
            let cutoff = Date.now.addingTimeInterval(-newShowWindow)
            let newShows = Set(((try? await shows) ?? []).filter { ($0.dateCreated ?? .distantPast) > cutoff }.map(\.id))
            return Array(group(episodes, excluding: newShows).prefix(limit))
        }
    }

    static func query(_ type: ItemKind, library: String, limit: Int) -> ItemQuery {
        var q = ItemQuery(parentId: library, includeItemTypes: [type], sortBy: ["DateCreated", "SortName"], sortOrder: .descending)
        q.limit = limit
        q.fields = ItemField.card + [.dateCreated]
        return q
    }

    /// Newest first, one card per show: its newest episode, and how many
    /// came within a fortnight of it.
    static func group(_ episodes: [BaseItem], excluding newShows: Set<String>) -> [Arrival] {
        var order: [String] = []
        var byShow: [String: [BaseItem]] = [:]
        for ep in episodes {
            guard let show = ep.seriesId, !newShows.contains(show) else { continue }
            if byShow[show] == nil { order.append(show) }
            byShow[show, default: []].append(ep)
        }
        return order.compactMap { show in
            guard let eps = byShow[show], let newest = eps.first else { return nil }
            let added = newest.dateCreated ?? .distantPast
            let count = eps.filter { ($0.dateCreated ?? .distantPast) > added.addingTimeInterval(-14 * 86_400) }.count
            return Arrival(card: showCard(from: newest), episode: newest, added: added, newEpisodes: count)
        }
    }

    /// The show, as its episode describes it (its art, its name).
    static func showCard(from ep: BaseItem) -> BaseItem {
        var show = BaseItem(id: ep.seriesId ?? ep.id, name: ep.seriesName ?? ep.name, kind: .series)
        var tags: [String: String] = [:]
        if ep.parentThumbItemId == ep.seriesId, let thumb = ep.parentThumbImageTag { tags["Thumb"] = thumb }
        if let primary = ep.seriesPrimaryImageTag { tags["Primary"] = primary }
        show.imageTags = tags
        if ep.parentBackdropItemId == ep.seriesId { show.backdropImageTags = ep.parentBackdropImageTags }
        return show
    }

    /// "This Week", "Last Week", "Earlier This Month", "Earlier".
    static func buckets(_ arrivals: [Arrival], now: Date = .now, calendar: Calendar = .current) -> [(title: String, arrivals: [Arrival])] {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: week) ?? week
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        func bucket(_ d: Date) -> String {
            if d >= week { return "This Week" }
            if d >= lastWeek { return "Last Week" }
            if d >= month { return "Earlier This Month" }
            return "Earlier"
        }
        var out: [(title: String, arrivals: [Arrival])] = []
        for a in arrivals {
            let b = bucket(a.added)
            if out.last?.title == b { out[out.count - 1].arrivals.append(a) } else { out.append((b, [a])) }
        }
        return out
    }

    /// On the art: "+3 episodes" (a show with new episodes; nothing on the rest).
    static func badge(_ a: Arrival) -> String? {
        guard let n = a.newEpisodes else { return nil }
        return n == 1 ? "+1 episode" : "+\(n) episodes"
    }

    /// Under the title: "Season 2 · Monday", "Added Tuesday".
    static func caption(_ a: Arrival, now: Date = .now, calendar: Calendar = .current) -> String {
        let when = day(a.added, now: now, calendar: calendar)
        if let season = a.episode?.parentIndexNumber { return "Season \(season) · \(when)" }
        return "Added \(when.lowercasedFirstIfDay)"
    }

    /// "Today", "Yesterday", "Tuesday" (this week), "Mar 3".
    static func day(_ d: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) { return "Yesterday" }
        if now.timeIntervalSince(d) < 6 * 86_400 { return d.formatted(.dateTime.weekday(.wide)) }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The line under the title: what this week brought, or the latest.
    static func lede(_ kind: ArrivalKind, _ arrivals: [Arrival], now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let latest = arrivals.first else { return nil }
        let words = Editorial(now: now, calendar: calendar, userName: nil)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let n = arrivals.filter { $0.added >= week }.count
        let name = latest.card.name ?? "Something"
        if n == 0 { return "Most recently, \(name), \(day(latest.added, now: now, calendar: calendar).lowercasedFirstIfDay)." }
        let number = words.number(n)
        let count = number.prefix(1).uppercased() + number.dropFirst()
        switch kind {
        case .episodes: return n == 1 ? "One show has new episodes this week." : "\(count) shows have new episodes this week."
        case .shows: return n == 1 ? "One show added this week." : "\(count) shows added this week."
        case .movies: return n == 1 ? "One film added this week." : "\(count) films added this week."
        }
    }
}

nonisolated private extension String {
    /// "Today" → "today" mid-sentence; "Tuesday", "Mar 3" stay.
    var lowercasedFirstIfDay: String {
        ["Today", "Yesterday"].contains(self) ? lowercased() : self
    }
}

/// A card for an arrival: "+3 episodes" on the art, "Season 2 · Monday"
/// under the name. A show with new episodes opens at its season.
struct ArrivalCard: View {
    let arrival: Arrival
    let width: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.navigate) private var navigate

    var body: some View {
        LandscapeCard(arrival.card, width: width, caption: Arrivals.caption(arrival), badge: Arrivals.badge(arrival)) {
            if let episode = arrival.episode { navigate(.item(episode)) } else { app.select(arrival.card, navigate: navigate) }
        }
        .contextMenu { ItemContextMenu(item: arrival.episode ?? arrival.card) }
    }
}

/// "View all" from New Episodes, New Shows or New Movies: the same name,
/// grouped by when they came, newest first.
struct ArrivalsPage: View {
    let spec: ArrivalsSpec
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.pageWidth) private var width
    @State private var arrivals: [Arrival]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(spec.title).font(.system(size: Layout.pageTitleSmall, weight: .bold)).foregroundStyle(theme.primaryText)
                    if let arrivals, let lede = Arrivals.lede(spec.kind, arrivals) {
                        Text(lede).font(.pageLede).foregroundStyle(theme.secondaryText).transition(.opacity)
                    }
                }
                let columns = Layout.columns(width, minWidth: Layout.landscapeMin, max: 4)
                let cardWidth = Layout.cardWidth(width, columns: columns)
                ForEach(Arrivals.buckets(arrivals ?? []), id: \.title) { bucket in
                    VStack(alignment: .leading, spacing: 18) {
                        Text(bucket.title).font(.sectionTitle).foregroundStyle(theme.primaryText)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: Layout.cardSpacing, alignment: .top), count: columns),
                                  alignment: .leading, spacing: Layout.shelfSpacing + 8) {
                            ForEach(bucket.arrivals) { ArrivalCard(arrival: $0, width: cardWidth) }
                        }
                    }
                    .tvFocusSection()
                }
                if arrivals?.isEmpty == true {
                    Text("Nothing new yet.").font(.callout).foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, Layout.horizontalMargin)
            .padding(.vertical, 50)
        }
        .tvScrollClipDisabled()
        .background(theme.backgroundGradient.ignoresSafeArea())
        .hidesNavigationBar()
        .animation(.easeOut(duration: 0.2), value: arrivals)
        .task {
            guard let client = app.session?.client else { return }
            arrivals = (try? await Arrivals.fetch(spec.kind, library: spec.libraryId, client: client, limit: 200)) ?? []
        }
    }
}
