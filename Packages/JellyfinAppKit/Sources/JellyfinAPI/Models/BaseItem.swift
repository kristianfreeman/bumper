public import Foundation

/// Jellyfin's `BaseItemKind`. Unknown future kinds decode to `.unknown`
/// rather than failing the whole page.
public enum ItemKind: String, Codable, Sendable, Hashable, CaseIterable {
    case movie = "Movie"
    case series = "Series"
    case season = "Season"
    case episode = "Episode"
    case boxSet = "BoxSet"
    case collectionFolder = "CollectionFolder"
    case folder = "Folder"
    case userView = "UserView"
    case video = "Video"
    case musicVideo = "MusicVideo"
    case trailer = "Trailer"
    case person = "Person"
    case playlist = "Playlist"
    case tvChannel = "TvChannel"
    case program = "Program"
    case audio = "Audio"
    case musicAlbum = "MusicAlbum"
    case musicArtist = "MusicArtist"
    case audioBook = "AudioBook"
    case book = "Book"
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemKind(rawValue: raw) ?? .unknown
    }

    public var isPlayable: Bool {
        switch self {
        case .movie, .episode, .video, .musicVideo, .trailer, .tvChannel, .program: true
        default: false
        }
    }
}

public enum ImageType: String, Codable, Sendable, Hashable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case thumb = "Thumb"
    case logo = "Logo"
    case banner = "Banner"
    case art = "Art"
    case disc = "Disc"
    case screenshot = "Screenshot"
    case chapter = "Chapter"
}

/// The subset of `BaseItemDto` the app actually renders. Requesting only the
/// `fields` we need (see `ItemFields`) keeps payloads small; decoding only the
/// keys below keeps parsing fast.
public struct BaseItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String?
    public var originalTitle: String?
    public var serverId: String?
    public var kind: ItemKind
    public var collectionType: String?
    public var overview: String?
    public var taglines: [String]?
    public var genres: [String]?
    public var productionYear: Int?
    public var premiereDate: Date?
    /// When it was added to the library (Fields=DateCreated).
    public var dateCreated: Date?
    public var endDate: Date?
    public var officialRating: String?
    public var communityRating: Double?
    public var criticRating: Double?
    public var runTimeTicks: Int64?
    public var indexNumber: Int?
    public var indexNumberEnd: Int?
    public var parentIndexNumber: Int?
    public var seriesId: String?
    public var seriesName: String?
    public var seasonId: String?
    public var seasonName: String?
    public var parentId: String?
    public var isFolder: Bool?
    public var childCount: Int?
    public var recursiveItemCount: Int?
    public var status: String?
    public var container: String?
    public var mediaType: String?
    public var primaryImageAspectRatio: Double?
    public var width: Int?
    public var height: Int?

    // Images
    public var imageTags: [String: String]?
    public var backdropImageTags: [String]?
    public var parentBackdropItemId: String?
    public var parentBackdropImageTags: [String]?
    public var parentThumbItemId: String?
    public var parentThumbImageTag: String?
    public var parentLogoItemId: String?
    public var parentLogoImageTag: String?
    public var seriesPrimaryImageTag: String?
    public var seriesThumbImageTag: String?
    public var imageBlurHashes: [String: [String: String]]?

    public var userData: UserItemData?
    public var mediaSources: [MediaSource]?
    public var mediaStreams: [MediaStream]?
    public var people: [Person]?
    public var studios: [NameIdPair]?
    public var chapters: [Chapter]?
    /// mediaSourceId → width → info
    public var trickplay: [String: [String: TrickplayInfo]]?
    public var remoteTrailers: [MediaURL]?
    /// External ids: "Tvdb", "Tmdb", "Imdb", …
    public var providerIds: [String: String]?
    /// A person's birthplace (their page asks for it).
    public var productionLocations: [String]?
    /// What kind of extra this is ("BehindTheScenes", "DeletedScene", …).
    public var extraType: String?
    // Audio / audiobooks: the author is the album artist; a multi-file book's
    // parts share an album (the book).
    public var album: String?
    public var albumArtist: String?
    public var artists: [String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", originalTitle = "OriginalTitle", serverId = "ServerId", kind = "Type"
        case collectionType = "CollectionType", overview = "Overview", taglines = "Taglines", genres = "Genres"
        case productionYear = "ProductionYear", premiereDate = "PremiereDate", endDate = "EndDate", dateCreated = "DateCreated"
        case officialRating = "OfficialRating", communityRating = "CommunityRating", criticRating = "CriticRating"
        case runTimeTicks = "RunTimeTicks", indexNumber = "IndexNumber", indexNumberEnd = "IndexNumberEnd"
        case parentIndexNumber = "ParentIndexNumber", seriesId = "SeriesId", seriesName = "SeriesName"
        case seasonId = "SeasonId", seasonName = "SeasonName", parentId = "ParentId", isFolder = "IsFolder"
        case childCount = "ChildCount", recursiveItemCount = "RecursiveItemCount", status = "Status"
        case container = "Container", mediaType = "MediaType", primaryImageAspectRatio = "PrimaryImageAspectRatio"
        case width = "Width", height = "Height"
        case imageTags = "ImageTags", backdropImageTags = "BackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId", parentBackdropImageTags = "ParentBackdropImageTags"
        case parentThumbItemId = "ParentThumbItemId", parentThumbImageTag = "ParentThumbImageTag"
        case parentLogoItemId = "ParentLogoItemId", parentLogoImageTag = "ParentLogoImageTag"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag", seriesThumbImageTag = "SeriesThumbImageTag"
        case imageBlurHashes = "ImageBlurHashes"
        case userData = "UserData", mediaSources = "MediaSources", mediaStreams = "MediaStreams"
        case people = "People", studios = "Studios", chapters = "Chapters", trickplay = "Trickplay"
        case remoteTrailers = "RemoteTrailers", providerIds = "ProviderIds"
        case productionLocations = "ProductionLocations", extraType = "ExtraType"
        case album = "Album", albumArtist = "AlbumArtist", artists = "Artists"
    }

    public init(id: String, name: String?, kind: ItemKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.userData == b.userData && a.name == b.name
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Derived presentation helpers

extension BaseItem {
    public static let ticksPerSecond: Int64 = 10_000_000

    public var runtime: Duration? {
        runTimeTicks.map { .ticks($0) }
    }

    public var resumePosition: Duration? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return .ticks(ticks)
    }

    /// 0...1, or nil if not started.
    public var progress: Double? {
        if let pct = userData?.playedPercentage, pct > 0 { return min(pct / 100, 1) }
        guard let pos = userData?.playbackPositionTicks, let total = runTimeTicks, total > 0, pos > 0 else { return nil }
        return min(Double(pos) / Double(total), 1)
    }

    public var isPlayed: Bool { userData?.played ?? false }
    /// An episode the user hasn't finished: its still and description can
    /// give the plot away.
    public var isSpoilerSensitive: Bool { kind == .episode && !isPlayed }
    public var isFavorite: Bool { userData?.isFavorite ?? false }

    /// "S2 · E5" style label for episodes.
    public var episodeLabel: String? {
        guard kind == .episode else { return nil }
        switch (parentIndexNumber, indexNumber) {
        case let (s?, e?): return "S\(s) · E\(e)"
        case let (nil, e?): return "E\(e)"
        default: return nil
        }
    }

    public func blurHash(for type: ImageType, tag: String?) -> String? {
        guard let tag else { return imageBlurHashes?[type.rawValue]?.values.first }
        return imageBlurHashes?[type.rawValue]?[tag]
    }
}

extension Duration {
    public static func ticks(_ ticks: Int64) -> Duration {
        .nanoseconds(ticks * 100)
    }

    public var ticks: Int64 {
        let (s, atto) = components
        return s * 10_000_000 + atto / 100_000_000_000
    }
}

public struct UserItemData: Codable, Sendable, Hashable {
    public var playbackPositionTicks: Int64?
    public var playCount: Int?
    public var isFavorite: Bool?
    public var played: Bool?
    public var playedPercentage: Double?
    public var unplayedItemCount: Int?
    public var lastPlayedDate: Date?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks", playCount = "PlayCount", isFavorite = "IsFavorite"
        case played = "Played", playedPercentage = "PlayedPercentage", unplayedItemCount = "UnplayedItemCount"
        case lastPlayedDate = "LastPlayedDate"
    }

    public init(playbackPositionTicks: Int64? = nil, isFavorite: Bool? = nil, played: Bool? = nil, playedPercentage: Double? = nil) {
        self.playbackPositionTicks = playbackPositionTicks
        self.isFavorite = isFavorite
        self.played = played
        self.playedPercentage = playedPercentage
    }
}

public struct Person: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String?
    public var role: String?
    public var type: String?
    public var primaryImageTag: String?
    public var imageBlurHashes: [String: [String: String]]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", role = "Role", type = "Type", primaryImageTag = "PrimaryImageTag"
        case imageBlurHashes = "ImageBlurHashes"
    }

    public init(id: String, name: String?, role: String? = nil, type: String? = nil, primaryImageTag: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.primaryImageTag = primaryImageTag
    }
}

public struct NameIdPair: Codable, Sendable, Hashable {
    public var id: String?
    public var name: String?
    enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
}

public struct MediaURL: Codable, Sendable, Hashable {
    public var url: String?
    public var name: String?
    enum CodingKeys: String, CodingKey { case url = "Url", name = "Name" }

    public init(url: String?, name: String? = nil) {
        self.url = url
        self.name = name
    }
}

public struct Chapter: Codable, Sendable, Hashable {
    public var startPositionTicks: Int64
    public var name: String?
    public var imageTag: String?
    enum CodingKeys: String, CodingKey { case startPositionTicks = "StartPositionTicks", name = "Name", imageTag = "ImageTag" }

    public init(startPositionTicks: Int64, name: String?, imageTag: String? = nil) {
        self.startPositionTicks = startPositionTicks
        self.name = name
        self.imageTag = imageTag
    }
}

/// Trickplay (scrubbing thumbnail) tile sheet description, Jellyfin 10.9+.
public struct TrickplayInfo: Codable, Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var tileWidth: Int
    public var tileHeight: Int
    public var thumbnailCount: Int
    /// Milliseconds between thumbnails.
    public var interval: Int
    public var bandwidth: Int?

    enum CodingKeys: String, CodingKey {
        case width = "Width", height = "Height", tileWidth = "TileWidth", tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount", interval = "Interval", bandwidth = "Bandwidth"
    }

    public var thumbnailsPerTile: Int { tileWidth * tileHeight }
}

/// Paged query response (`/Items`, etc.).
public struct ItemsPage: Codable, Sendable {
    public var items: [BaseItem]
    public var totalRecordCount: Int
    public var startIndex: Int

    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount", startIndex = "StartIndex" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([BaseItem].self, forKey: .items) ?? []
        totalRecordCount = try c.decodeIfPresent(Int.self, forKey: .totalRecordCount) ?? items.count
        startIndex = try c.decodeIfPresent(Int.self, forKey: .startIndex) ?? 0
    }

    public init(items: [BaseItem], totalRecordCount: Int, startIndex: Int = 0) {
        self.items = items
        self.totalRecordCount = totalRecordCount
        self.startIndex = startIndex
    }
}
