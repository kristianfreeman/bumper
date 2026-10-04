import Foundation
public import JellyfinAPI

/// Deterministic fake library: same seed → same titles, ids, images, every
/// run. Perf numbers from UI tests are only comparable if the data is.
public struct MockCatalog: Sendable {
    public let movies: [BaseItem]
    public let series: [BaseItem]
    public let seasons: [String: [BaseItem]]     // seriesId → seasons
    public let episodes: [String: [BaseItem]]    // seasonId → episodes
    public let views: [BaseItem]
    public let genres = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Science Fiction", "Thriller", "Western"]

    public static let moviesViewId = "view-movies"
    public static let showsViewId = "view-shows"

    public static let shared = MockCatalog(movieCount: 600, seriesCount: 48)

    public init(movieCount: Int, seriesCount: Int) {
        var rng = SplitMix64(seed: 0x5EED)
        let adjectives = ["Silent", "Crimson", "Hidden", "Last", "Electric", "Broken", "Golden", "Midnight", "Distant", "Iron", "Paper", "Endless", "Northern", "Burning", "Glass", "Velvet", "Hollow", "Neon", "Quiet", "Wild"]
        let nouns = ["Harbor", "Signal", "Kingdom", "Orchard", "Frontier", "Machine", "River", "Witness", "Garden", "Empire", "Archive", "Horizon", "Station", "Voyage", "Labyrinth", "Comet", "Tide", "Atlas", "Mirror", "Engine"]
        func title() -> String {
            let a = adjectives[Int(rng.next() % UInt64(adjectives.count))]
            let n = nouns[Int(rng.next() % UInt64(nouns.count))]
            return rng.next() % 3 == 0 ? "The \(a) \(n)" : "\(a) \(n)"
        }
        let genres = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Science Fiction", "Thriller", "Western"]
        func genreSet() -> [String] {
            let a = genres[Int(rng.next() % UInt64(genres.count))]
            let b = genres[Int(rng.next() % UInt64(genres.count))]
            return a == b ? [a] : [a, b]
        }
        let overview = "A meticulously generated story used to exercise layout, truncation and performance. Nothing here is real, but every pixel is measured."

        var movies: [BaseItem] = []
        for i in 0..<movieCount {
            var m = BaseItem(id: "movie-" + pad(i, 4), name: "\(title()) \(i % 7 == 0 ? "II" : "")".trimmingCharacters(in: .whitespaces), kind: .movie)
            m.productionYear = 1970 + Int(rng.next() % 56)
            m.runTimeTicks = Int64(80 + Int(rng.next() % 90)) * 60 * BaseItem.ticksPerSecond
            m.overview = overview
            m.genres = genreSet()
            m.officialRating = ["G", "PG", "PG-13", "R", "TV-MA"][Int(rng.next() % 5)]
            m.communityRating = Double(50 + Int(rng.next() % 45)) / 10
            m.imageTags = ["Primary": "p\(i)", "Thumb": "t\(i)"]
            m.backdropImageTags = ["b\(i)"]
            m.imageBlurHashes = ["Primary": ["p\(i)": MockCatalog.blurHashes[i % MockCatalog.blurHashes.count]], "Backdrop": ["b\(i)": MockCatalog.blurHashes[(i + 3) % MockCatalog.blurHashes.count]]]
            m.parentId = Self.moviesViewId
            m.premiereDate = Date(timeIntervalSince1970: TimeInterval(1_600_000_000 - i * 86_400))
            m.dateCreated = Date.now.addingTimeInterval(-Double(i) * 1.5 * 86_400)
            var ud = UserItemData(isFavorite: i % 23 == 0, played: i % 5 == 0)
            if i % 9 == 1 { ud.playbackPositionTicks = m.runTimeTicks! / Int64(2 + i % 5); ud.playedPercentage = 100 / Double(2 + i % 5) }
            m.userData = ud
            movies.append(m)
        }

        var series: [BaseItem] = []
        var seasons: [String: [BaseItem]] = [:]
        var episodes: [String: [BaseItem]] = [:]
        for i in 0..<seriesCount {
            let sid = "series-" + pad(i, 3)
            var s = BaseItem(id: sid, name: title(), kind: .series)
            s.productionYear = 1995 + Int(rng.next() % 30)
            s.overview = overview
            s.genres = genreSet()
            s.imageTags = ["Primary": "sp\(i)", "Thumb": "st\(i)"]
            s.backdropImageTags = ["sb\(i)"]
            s.imageBlurHashes = ["Primary": ["sp\(i)": MockCatalog.blurHashes[(i + 5) % MockCatalog.blurHashes.count]]]
            s.parentId = Self.showsViewId
            s.status = i % 3 == 0 ? "Continuing" : "Ended"
            s.providerIds = ["Tvdb": "76568"]                 // a real id: online theme fallback works
            let seasonCount = 1 + i % 4
            var unplayed = 0
            var seasonList: [BaseItem] = []
            for sn in 1...seasonCount {
                let seasonId = "\(sid)-s\(sn)"
                var season = BaseItem(id: seasonId, name: "Season \(sn)", kind: .season)
                season.indexNumber = sn
                season.seriesId = sid
                season.seriesName = s.name
                season.imageTags = ["Primary": "ssp\(i)-\(sn)"]
                var eps: [BaseItem] = []
                for e in 1...(6 + (i + sn) % 7) {
                    var ep = BaseItem(id: "\(seasonId)-e\(e)", name: "Chapter \(e): \(title())", kind: .episode)
                    ep.indexNumber = e
                    ep.parentIndexNumber = sn
                    ep.seriesId = sid
                    ep.seriesName = s.name
                    ep.seasonId = seasonId
                    ep.overview = overview
                    ep.runTimeTicks = Int64(22 + (e * 7) % 40) * 60 * BaseItem.ticksPerSecond
                    ep.imageTags = ["Primary": "ep\(i)-\(sn)-\(e)"]
                    ep.imageBlurHashes = ["Primary": ["ep\(i)-\(sn)-\(e)": MockCatalog.blurHashes[(i + sn + e) % MockCatalog.blurHashes.count]]]
                    ep.seriesPrimaryImageTag = "sp\(i)"
                    ep.parentBackdropItemId = sid
                    ep.parentBackdropImageTags = ["sb\(i)"]
                    let played = sn < seasonCount || e < 3
                    if !played { unplayed += 1 }
                    ep.userData = UserItemData(playbackPositionTicks: e == 3 && sn == seasonCount ? ep.runTimeTicks! / 3 : nil, played: played)
                    eps.append(ep)
                }
                episodes[seasonId] = eps
                season.childCount = eps.count
                seasonList.append(season)
            }
            seasons[sid] = seasonList
            s.childCount = seasonCount
            s.userData = UserItemData(played: unplayed == 0)
            s.userData?.unplayedItemCount = unplayed
            series.append(s)
        }

        var moviesView = BaseItem(id: Self.moviesViewId, name: "Movies", kind: .collectionFolder)
        moviesView.collectionType = "movies"
        moviesView.imageTags = ["Primary": "vm"]
        var showsView = BaseItem(id: Self.showsViewId, name: "TV Shows", kind: .collectionFolder)
        showsView.collectionType = "tvshows"
        showsView.imageTags = ["Primary": "vs"]

        self.movies = movies
        self.series = series
        self.seasons = seasons
        self.episodes = episodes
        self.views = [moviesView, showsView]
    }

    public var allItems: [BaseItem] { movies + series + seasons.values.flatMap { $0 } + episodes.values.flatMap { $0 } }

    public func item(id: String) -> BaseItem? {
        if let m = movies.first(where: { $0.id == id }) { return m }
        if let s = series.first(where: { $0.id == id }) { return s }
        for list in seasons.values { if let s = list.first(where: { $0.id == id }) { return s } }
        for list in episodes.values { if let e = list.first(where: { $0.id == id }) { return e } }
        return views.first { $0.id == id }
    }

    static let blurHashes = [
        "LEHV6nWB2yk8pyo0adR*.7kCMdnj", "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.", "L6PZfSi_.AyE_3t7t7R**0o#DgR4",
        "LKN]Rv%2Tw=w]~RBVZRi};RPxuwH", "LlMF%n00%#MwS|WCWEM{R*bbWBbH", "L35#bB~qIUxu00M{t7of4nRj%Mof",
        "LBAdAqof00WCqZj[PDay0.WB}pof", "LVC$sTRk00t7~qRjD%Rj4.WB%MRj",
    ]
}

func pad(_ n: Int, _ width: Int) -> String {
    let s = String(n)
    return String(repeating: "0", count: max(0, width - s.count)) + s
}

/// Tiny deterministic PRNG.
struct SplitMix64: Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
