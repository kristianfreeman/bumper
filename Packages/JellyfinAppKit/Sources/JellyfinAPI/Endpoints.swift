public import Foundation

/// `fields=` values. Ask for the minimum: every extra field costs server DB
/// time, bytes on the wire, and decode time.
public enum ItemField: String, Sendable, Codable {
    case overview = "Overview"
    case genres = "Genres"
    case people = "People"
    case studios = "Studios"
    case mediaSources = "MediaSources"
    case mediaStreams = "MediaStreams"
    case chapters = "Chapters"
    case trickplay = "Trickplay"
    case dateCreated = "DateCreated"
    case taglines = "Taglines"
    case primaryImageAspectRatio = "PrimaryImageAspectRatio"
    case childCount = "ChildCount"
    case recursiveItemCount = "RecursiveItemCount"
    case remoteTrailers = "RemoteTrailers"
    case originalTitle = "OriginalTitle"
    case providerIds = "ProviderIds"

    /// Enough for a shelf card: art + progress. (UserData, image tags and
    /// blurhashes come back without being asked for.)
    public static let card: [ItemField] = [.primaryImageAspectRatio]
    /// Enough for the focused-item hero header on top of a shelf.
    public static let hero: [ItemField] = [.overview, .genres, .primaryImageAspectRatio, .dateCreated]
    /// Full detail page.
    public static let detail: [ItemField] = [.overview, .genres, .people, .studios, .mediaSources, .mediaStreams, .chapters, .trickplay, .taglines, .childCount, .remoteTrailers, .originalTitle, .providerIds]
}

public enum ItemSortOrder: String, Sendable, Codable { case ascending = "Ascending", descending = "Descending" }

/// Builder for `/Items` queries.
public struct ItemQuery: Sendable, Hashable, Codable {
    public var parentId: String?
    public var includeItemTypes: [ItemKind] = []
    public var excludeItemTypes: [ItemKind] = []
    public var recursive: Bool = true
    public var sortBy: [String] = ["SortName"]
    public var sortOrder: ItemSortOrder = .ascending
    public var filters: [String] = []          // IsUnplayed, IsFavorite, IsResumable, IsPlayed
    public var genres: [String] = []
    public var searchTerm: String?
    public var nameStartsWith: String?
    /// Production years (a decade: ten of them).
    public var years: [Int]?
    public var minCommunityRating: Double?
    public var startIndex: Int = 0
    public var limit: Int? = 100
    public var fields: [ItemField] = ItemField.card
    public var imageTypes: [ImageType] = [.primary, .backdrop, .thumb, .logo]
    public var enableTotalRecordCount = true

    public init(parentId: String? = nil, includeItemTypes: [ItemKind] = [], sortBy: [String] = ["SortName"], sortOrder: ItemSortOrder = .ascending, limit: Int? = 100) {
        self.parentId = parentId
        self.includeItemTypes = includeItemTypes
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.limit = limit
    }

    func queryItems(userId: String?) -> [URLQueryItem] {
        var q: [URLQueryItem] = [
            .init(name: "userId", value: userId),
            .init(name: "parentId", value: parentId),
            .init(name: "recursive", value: String(recursive)),
            .init(name: "sortBy", value: sortBy.joined(separator: ",")),
            .init(name: "sortOrder", value: sortOrder.rawValue),
            .init(name: "startIndex", value: String(startIndex)),
            .init(name: "fields", value: fields.map(\.rawValue).joined(separator: ",")),
            .init(name: "enableImageTypes", value: imageTypes.map(\.rawValue).joined(separator: ",")),
            .init(name: "imageTypeLimit", value: "1"),
            .init(name: "enableTotalRecordCount", value: String(enableTotalRecordCount)),
        ]
        if let limit { q.append(.init(name: "limit", value: String(limit))) }
        if !includeItemTypes.isEmpty { q.append(.init(name: "includeItemTypes", value: includeItemTypes.map(\.rawValue).joined(separator: ","))) }
        if !excludeItemTypes.isEmpty { q.append(.init(name: "excludeItemTypes", value: excludeItemTypes.map(\.rawValue).joined(separator: ","))) }
        if !filters.isEmpty { q.append(.init(name: "filters", value: filters.joined(separator: ","))) }
        if !genres.isEmpty { q.append(.init(name: "genres", value: genres.joined(separator: "|"))) }
        if let searchTerm { q.append(.init(name: "searchTerm", value: searchTerm)) }
        if let nameStartsWith { q.append(.init(name: "nameStartsWith", value: nameStartsWith)) }
        if let years, !years.isEmpty { q.append(.init(name: "years", value: years.map(String.init).joined(separator: ","))) }
        if let minCommunityRating { q.append(.init(name: "minCommunityRating", value: String(minCommunityRating))) }
        return q
    }
}

private func encode<T: Encodable>(_ value: T) -> Data? {
    try? JSONEncoder.jellyfin.encode(value)
}

private func cardQuery(_ fields: [ItemField] = ItemField.card) -> [URLQueryItem] {
    [
        .init(name: "fields", value: fields.map(\.rawValue).joined(separator: ",")),
        .init(name: "enableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
        .init(name: "imageTypeLimit", value: "1"),
    ]
}

// MARK: - System & auth

extension JellyfinClient {
    public func publicSystemInfo() async throws -> PublicSystemInfo {
        try await send(Request(.get, "/System/Info/Public", timeout: 5))
    }

    public func publicUsers() async throws -> [UserDto] {
        try await send(Request(.get, "/Users/Public"))
    }

    public func authenticate(username: String, password: String) async throws -> AuthenticationResult {
        struct Body: Encodable { let Username: String; let Pw: String }
        return try await send(Request(.post, "/Users/AuthenticateByName", body: encode(Body(Username: username, Pw: password))))
    }

    public func quickConnectEnabled() async throws -> Bool {
        try await send(Request(.get, "/QuickConnect/Enabled"))
    }

    public func quickConnectInitiate() async throws -> QuickConnectState {
        try await send(Request(.post, "/QuickConnect/Initiate"))
    }

    public func quickConnectState(secret: String) async throws -> QuickConnectState {
        try await send(Request(.get, "/QuickConnect/Connect", query: [.init(name: "secret", value: secret)]))
    }

    public func authenticate(quickConnectSecret secret: String) async throws -> AuthenticationResult {
        struct Body: Encodable { let Secret: String }
        return try await send(Request(.post, "/Users/AuthenticateWithQuickConnect", body: encode(Body(Secret: secret))))
    }

    public func currentUser() async throws -> UserDto {
        try await send(Request(.get, "/Users/Me"))
    }

    public func logout() async throws {
        try await send(Request<Void>(.post, "/Sessions/Logout"))
    }

    /// Tells the server what this client can do (remote control, device profile).
    public func reportCapabilities(deviceProfile: DeviceProfile) async throws {
        struct Body: Encodable {
            let PlayableMediaTypes = ["Video", "Audio"]
            let SupportedCommands = ["Play", "Playstate", "DisplayMessage", "SetAudioStreamIndex", "SetSubtitleStreamIndex"]
            let SupportsMediaControl = true
            let SupportsPersistentIdentifier = true
            let DeviceProfile: DeviceProfile
        }
        try await send(Request<Void>(.post, "/Sessions/Capabilities/Full", body: encode(Body(DeviceProfile: deviceProfile))))
    }
}

// MARK: - Browsing

extension JellyfinClient {
    public func userViews() async throws -> ItemsPage {
        try await send(Request(.get, "/UserViews", query: [.init(name: "userId", value: userId)] + cardQuery()))
    }

    public func items(_ query: ItemQuery) async throws -> ItemsPage {
        try await send(Request(.get, "/Items", query: query.queryItems(userId: userId)))
    }

    public func item(id: String, fields: [ItemField] = ItemField.detail) async throws -> BaseItem {
        try await send(Request(.get, "/Items/\(id)", query: [.init(name: "userId", value: userId)] + cardQuery(fields)))
    }

    public func resumeItems(limit: Int = 24, mediaTypes: String = "Video") async throws -> ItemsPage {
        try await send(Request(.get, "/UserItems/Resume", query: [
            .init(name: "userId", value: userId),
            .init(name: "limit", value: String(limit)),
            .init(name: "mediaTypes", value: mediaTypes),
            .init(name: "enableTotalRecordCount", value: "false"),
        ] + cardQuery(ItemField.hero)))
    }

    public func nextUp(limit: Int = 24, seriesId: String? = nil) async throws -> ItemsPage {
        try await send(Request(.get, "/Shows/NextUp", query: [
            .init(name: "userId", value: userId),
            .init(name: "limit", value: String(limit)),
            .init(name: "seriesId", value: seriesId),
            .init(name: "enableTotalRecordCount", value: "false"),
            .init(name: "enableResumable", value: "false"),
            .init(name: "enableRewatching", value: "false"),
        ] + cardQuery(ItemField.hero)))
    }

    public func latest(parentId: String?, limit: Int = 24) async throws -> [BaseItem] {
        try await send(Request(.get, "/Items/Latest", query: [
            .init(name: "userId", value: userId),
            .init(name: "parentId", value: parentId),
            .init(name: "limit", value: String(limit)),
            .init(name: "groupItems", value: "true"),
        ] + cardQuery(ItemField.hero)))
    }

    public func seasons(seriesId: String) async throws -> ItemsPage {
        try await send(Request(.get, "/Shows/\(seriesId)/Seasons", query: [.init(name: "userId", value: userId)] + cardQuery([.childCount])))
    }

    public func episodes(seriesId: String, seasonId: String?) async throws -> ItemsPage {
        try await send(Request(.get, "/Shows/\(seriesId)/Episodes", query: [
            .init(name: "userId", value: userId),
            .init(name: "seasonId", value: seasonId),
        ] + cardQuery([.overview])))
    }

    public func similar(to id: String, limit: Int = 16) async throws -> ItemsPage {
        try await send(Request(.get, "/Items/\(id)/Similar", query: [
            .init(name: "userId", value: userId),
            .init(name: "limit", value: String(limit)),
        ] + cardQuery()))
    }

    public func genres(parentId: String?) async throws -> ItemsPage {
        try await send(Request(.get, "/Genres", query: [
            .init(name: "userId", value: userId),
            .init(name: "parentId", value: parentId),
            .init(name: "sortBy", value: "SortName"),
        ]))
    }

    public func search(_ term: String, limit: Int = 40) async throws -> ItemsPage {
        var q = ItemQuery(includeItemTypes: [.movie, .series, .episode, .boxSet], limit: limit)
        q.searchTerm = term
        q.sortBy = []
        q.enableTotalRecordCount = false
        return try await items(q)
    }

    /// Theme songs for an item (series/movie). `inheritFromParent` lets a
    /// season or episode use its series' theme.
    public func themeSongs(itemId: String) async throws -> [BaseItem] {
        struct Result: Decodable, Sendable {
            let items: [BaseItem]
            enum CodingKeys: String, CodingKey { case items = "Items" }
        }
        let r: Result = try await send(Request(.get, "/Items/\(itemId)/ThemeSongs", query: [
            .init(name: "userId", value: userId),
            .init(name: "inheritFromParent", value: "true"),
        ]))
        return r.items
    }

    /// An audiobook file as an MP3 stream starting at `start`: the server's
    /// transcoder seeks, so any position starts at once, and every source
    /// format (M4B, MP3, FLAC, Opus…) arrives as one the app decodes itself
    /// (it has to, for Smart Speed).
    public func audiobookStreamURL(itemId: String, start: Double) -> URL {
        url("/Audio/\(itemId)/stream.mp3", query: [
            .init(name: "static", value: "false"),
            .init(name: "audioCodec", value: "mp3"),
            .init(name: "audioBitRate", value: "96000"),
            .init(name: "audioChannels", value: "2"),
            .init(name: "startTimeTicks", value: String(Int64(start * 10_000_000))),
            .init(name: "userId", value: userId),
            .init(name: "deviceId", value: clientInfo.deviceId),
            .init(name: "api_key", value: accessToken),
        ])
    }

    /// Audio the device can play as-is, or a server transcode to AAC when not.
    public func universalAudioURL(itemId: String) -> URL {
        url("/Audio/\(itemId)/universal", query: [
            .init(name: "userId", value: userId),
            .init(name: "deviceId", value: clientInfo.deviceId),
            .init(name: "container", value: "mp3,aac,m4a|aac,m4b|aac,flac,alac,m4a|alac,wav"),
            .init(name: "audioCodec", value: "aac"),
            .init(name: "transcodingContainer", value: "mp4"),
            .init(name: "transcodingProtocol", value: "http"),
            .init(name: "api_key", value: accessToken),
        ])
    }

    public func setPlayed(_ played: Bool, itemId: String) async throws {
        try await send(Request<Void>(played ? .post : .delete, "/UserPlayedItems/\(itemId)", query: [.init(name: "userId", value: userId)]))
    }

    public func setFavorite(_ favorite: Bool, itemId: String) async throws {
        try await send(Request<Void>(favorite ? .post : .delete, "/UserFavoriteItems/\(itemId)", query: [.init(name: "userId", value: userId)]))
    }
}

// MARK: - Playback

extension JellyfinClient {
    public func playbackInfo(itemId: String, request: PlaybackInfoRequest) async throws -> PlaybackInfoResponse {
        try await send(Request(.post, "/Items/\(itemId)/PlaybackInfo", query: [.init(name: "userId", value: userId)], body: encode(request)))
    }

    public func mediaSegments(itemId: String) async throws -> [MediaSegment] {
        let page: MediaSegmentsPage = try await send(Request(.get, "/MediaSegments/\(itemId)"))
        return page.items
    }

    /// Intro Skipper plugin's own endpoint (versions that predate, or run
    /// without, Jellyfin's MediaSegments). Seconds, with a validity flag.
    public func introSkipperSegments(episodeId: String) async throws -> [MediaSegment] {
        struct Entry: Decodable, Sendable {
            let valid: Bool?
            let introStart: Double?
            let introEnd: Double?
            enum CodingKeys: String, CodingKey { case valid = "Valid", introStart = "IntroStart", introEnd = "IntroEnd" }
        }
        let result: [String: Entry] = try await send(Request(.get, "/Episode/\(episodeId)/IntroSkipperSegments"))
        let kinds: [String: MediaSegment.Kind] = ["Introduction": .intro, "Credits": .outro, "Recap": .recap, "Preview": .preview]
        return result.compactMap { name, e in
            guard e.valid != false, let kind = kinds[name], let s = e.introStart, let end = e.introEnd, end > s else { return nil }
            return MediaSegment(id: "skipper-\(name)", itemId: episodeId, type: kind,
                                startTicks: Int64(s * Double(BaseItem.ticksPerSecond)), endTicks: Int64(end * Double(BaseItem.ticksPerSecond)))
        }
    }

    public func reportPlaybackStart(_ report: PlaybackProgressReport) async throws {
        try await send(Request<Void>(.post, "/Sessions/Playing", body: encode(report)))
    }

    public func reportPlaybackProgress(_ report: PlaybackProgressReport) async throws {
        try await send(Request<Void>(.post, "/Sessions/Playing/Progress", body: encode(report)))
    }

    public func reportPlaybackStopped(_ report: PlaybackProgressReport) async throws {
        try await send(Request<Void>(.post, "/Sessions/Playing/Stopped", body: encode(report)))
    }

    /// Original file, byte-for-byte (`static=true`): supports HTTP range
    /// requests, which both AVPlayer and VLCKit rely on.
    public func directStreamURL(itemId: String, mediaSourceId: String, container: String?, playSessionId: String?) -> URL {
        let ext = container?.split(separator: ",").first.map { ".\($0)" } ?? ""
        return url("/Videos/\(itemId)/stream\(ext)", query: [
            .init(name: "static", value: "true"),
            .init(name: "mediaSourceId", value: mediaSourceId),
            .init(name: "playSessionId", value: playSessionId),
            .init(name: "deviceId", value: clientInfo.deviceId),
            .init(name: "api_key", value: accessToken),
        ])
    }

    /// Server-relative URLs returned in PlaybackInfo (TranscodingUrl, DeliveryUrl).
    public func absoluteURL(serverRelative path: String) -> URL? {
        if let url = URL(string: path), url.scheme != nil { return url }
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        return URL(string: base + path)
    }

    public func subtitleURL(itemId: String, mediaSourceId: String, streamIndex: Int, format: String) -> URL {
        url("/Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(streamIndex)/0/Stream.\(format)", query: [.init(name: "api_key", value: accessToken)])
    }

    public func trickplayTileURL(itemId: String, mediaSourceId: String, width: Int, index: Int) -> URL {
        url("/Videos/\(itemId)/Trickplay/\(width)/\(index).jpg", query: [
            .init(name: "mediaSourceId", value: mediaSourceId),
            .init(name: "api_key", value: accessToken),
        ])
    }
}

// MARK: - Images

public struct ImageOptions: Sendable, Hashable {
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var quality: Int = 90
    public var format: String? = nil

    public init(maxWidth: Int? = nil, maxHeight: Int? = nil, quality: Int = 90) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.quality = quality
    }
}

extension JellyfinClient {
    /// Server-side resized image. Always pass a size: Jellyfin resizes and
    /// caches it, so we download and decode exactly the pixels we display.
    public func imageURL(itemId: String, type: ImageType, tag: String?, index: Int? = nil, options: ImageOptions) -> URL {
        let indexPath = index.map { "/\($0)" } ?? ""
        return url("/Items/\(itemId)/Images/\(type.rawValue)\(indexPath)", query: [
            .init(name: "tag", value: tag),
            .init(name: "maxWidth", value: options.maxWidth.map(String.init)),
            .init(name: "maxHeight", value: options.maxHeight.map(String.init)),
            .init(name: "quality", value: String(options.quality)),
            .init(name: "format", value: options.format),
        ])
    }

    /// Jellyfin 10.9+ (`/Users/{id}/Images/Primary` was removed).
    public func userImageURL(userId: String, tag: String?, size: Int) -> URL {
        url("/UserImage", query: [
            .init(name: "userId", value: userId),
            .init(name: "tag", value: tag),
            .init(name: "maxWidth", value: String(size)),
            .init(name: "quality", value: "90"),
        ])
    }
}

// MARK: - Subtitle search (the server's subtitle providers, e.g. the OpenSubtitles plugin)

/// A subtitle the server's providers found (`RemoteSubtitleInfo`).
public struct RemoteSubtitle: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var providerName: String?
    public var name: String?
    public var format: String?
    public var author: String?
    public var comment: String?
    public var communityRating: Double?
    public var frameRate: Double?
    public var downloadCount: Int?
    public var isHashMatch: Bool?
    public var aiTranslated: Bool?
    public var machineTranslated: Bool?
    public var forced: Bool?
    public var hearingImpaired: Bool?
    public var threeLetterISOLanguageName: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", providerName = "ProviderName", name = "Name", format = "Format", author = "Author", comment = "Comment"
        case communityRating = "CommunityRating", frameRate = "FrameRate", downloadCount = "DownloadCount", isHashMatch = "IsHashMatch"
        case aiTranslated = "AiTranslated", machineTranslated = "MachineTranslated", forced = "Forced", hearingImpaired = "HearingImpaired"
        case threeLetterISOLanguageName = "ThreeLetterISOLanguageName"
    }

    public init(id: String, providerName: String? = nil, name: String? = nil, format: String? = nil, frameRate: Double? = nil,
                downloadCount: Int? = nil, isHashMatch: Bool? = nil, hearingImpaired: Bool? = nil, threeLetterISOLanguageName: String? = nil) {
        self.id = id
        self.providerName = providerName
        self.name = name
        self.format = format
        self.frameRate = frameRate
        self.downloadCount = downloadCount
        self.isHashMatch = isHashMatch
        self.hearingImpaired = hearingImpaired
        self.threeLetterISOLanguageName = threeLetterISOLanguageName
    }
}

extension JellyfinClient {
    /// Searches the server's subtitle providers (needs one installed, e.g.
    /// the OpenSubtitles plugin, and the user allowed to manage subtitles).
    /// `language`: ISO 639-2 ("eng").
    public func remoteSubtitles(itemId: String, language: String) async throws -> [RemoteSubtitle] {
        try await send(Request(.get, "/Items/\(itemId)/RemoteSearch/Subtitles/\(language)", timeout: 30))
    }

    /// Has the server download one, beside the video; it appears as a new
    /// external subtitle stream on the item.
    public func downloadRemoteSubtitle(itemId: String, subtitleId: String) async throws {
        let id = subtitleId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? subtitleId
        try await send(Request<Void>(.post, "/Items/\(itemId)/RemoteSearch/Subtitles/\(id)"))
    }
}

// MARK: - Display preferences (Bumper's own synced state)

extension JellyfinClient {
    /// The user's custom display preferences for a client: a string map the
    /// server keeps per user, so every device signed in to the account sees
    /// the same values (Bumper keeps its queue there).
    public func customPreferences(id: String = "bumper", client: String = "bumper") async throws -> [String: String] {
        let raw = try await rawPreferences(id: id, client: client)
        let prefs = raw["CustomPrefs"] as? [String: Any] ?? [:]
        return prefs.compactMapValues { $0 as? String }
    }

    /// Sets some of them (others are kept), writing the whole record back.
    public func setCustomPreferences(_ values: [String: String], id: String = "bumper", client: String = "bumper") async throws {
        var raw = (try? await rawPreferences(id: id, client: client)) ?? [:]
        var prefs = raw["CustomPrefs"] as? [String: Any] ?? [:]
        for (k, v) in values { prefs[k] = v }
        raw["CustomPrefs"] = prefs
        raw["Id"] = raw["Id"] ?? id
        raw["Client"] = client
        // Fields the server requires on write.
        for (k, v) in ["SortBy": "SortName", "SortOrder": "Ascending", "ScrollDirection": "Horizontal"] where raw[k] == nil { raw[k] = v }
        for k in ["RememberIndexing", "RememberSorting", "ShowBackdrop", "ShowSidebar"] where raw[k] == nil { raw[k] = false }
        for k in ["PrimaryImageHeight", "PrimaryImageWidth"] where raw[k] == nil { raw[k] = 0 }
        let body = try JSONSerialization.data(withJSONObject: raw)
        try await send(Request<Void>(.post, "/DisplayPreferences/\(id)", query: [.init(name: "userId", value: userId), .init(name: "client", value: client)], body: body))
    }

    private func rawPreferences(id: String, client: String) async throws -> [String: Any] {
        let data = try await send(Request<Data>(.get, "/DisplayPreferences/\(id)", query: [.init(name: "userId", value: userId), .init(name: "client", value: client)]) { data, _ in data })
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
