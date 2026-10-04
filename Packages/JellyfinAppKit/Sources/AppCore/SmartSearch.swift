public import Foundation
public import JellyfinAPI
import Instrumentation

/// What the search service (services/search) understood from a request: a
/// filter to apply, or "this names a title".
public struct SearchIntent: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable { case title, browse }
    public enum Media: String, Sendable, Codable { case any, movie, series }

    public var kind: Kind
    public var media: Media = .any
    /// A canonical genre key ("comedy", "science_fiction"…).
    public var genre: String?
    public var decade: Int?
    public var maxMinutes: Int?
    public var minRating: Double?
    public var watched: CollectionFilter.Watched = .any
    public var added: CollectionFilter.Added = .any
    public var source: String?

    public init(kind: Kind, media: Media = .any, genre: String? = nil, decade: Int? = nil, maxMinutes: Int? = nil,
                minRating: Double? = nil, watched: CollectionFilter.Watched = .any, added: CollectionFilter.Added = .any) {
        self.kind = kind
        self.media = media
        self.genre = genre
        self.decade = decade
        self.maxMinutes = maxMinutes
        self.minRating = minRating
        self.watched = watched
        self.added = added
    }

    /// The service's genre keys, as the names libraries tend to use (first
    /// is the name to use when the library's genres aren't known).
    static let genreNames: [String: [String]] = [
        "comedy": ["Comedy"], "horror": ["Horror"], "action": ["Action", "Action & Adventure"],
        "adventure": ["Adventure", "Action & Adventure"], "romance": ["Romance"], "drama": ["Drama"],
        "mystery": ["Mystery"], "thriller": ["Thriller"], "crime": ["Crime"],
        "science_fiction": ["Science Fiction", "Sci-Fi", "Sci-Fi & Fantasy"], "fantasy": ["Fantasy", "Sci-Fi & Fantasy"],
        "animation": ["Animation"], "documentary": ["Documentary"], "family": ["Family", "Kids"],
        "western": ["Western"], "war": ["War", "War & Politics"], "history": ["History"], "music": ["Music", "Musical"],
    ]
}

extension CollectionFilter {
    /// Sets what the intent asks for (parts it doesn't mention are left as
    /// they are). Returns the parts it changed.
    @discardableResult
    public mutating func apply(_ intent: SearchIntent, genres: [String] = []) -> [Part] {
        var changed: [Part] = []
        if intent.watched != .any { watched = intent.watched; changed.append(.watched) }
        if intent.added != .any { added = intent.added; changed.append(.added) }
        if let decade = intent.decade { self.decade = decade; changed.append(.decade) }
        if let minutes = intent.maxMinutes { maxMinutes = minutes; changed.append(.length) }
        if let rating = intent.minRating { minRating = rating; changed.append(.rating) }
        if let key = intent.genre, let names = SearchIntent.genreNames[key] {
            genre = names.lazy.compactMap { name in genres.first { $0.caseInsensitiveCompare(name) == .orderedSame } }.first ?? names[0]
            changed.append(.genre)
        }
        // Films or shows: only narrows a page that holds both.
        let kinds: [ItemKind]? = switch intent.media {
        case .movie: [.movie]
        case .series: [.series]
        case .any: nil
        }
        if let kinds, base.includeItemTypes.count > 1, base.includeItemTypes.contains(kinds[0]) {
            base.includeItemTypes = kinds
            libraryName = intent.media == .movie ? "Movies" : "Shows"
        }
        return changed
    }
}

/// Words → a filter. Asks the search service when it's configured and up;
/// otherwise (or when it's slow or failing) reads the words on the device.
/// When neither finds anything to filter on, the words are a title: search
/// for them.
public actor SmartSearch {
    public enum Understanding: Sendable, Equatable {
        /// The filter to show, and the parts the words set.
        case filter(CollectionFilter, changed: [CollectionFilter.Part], fromService: Bool)
        /// A title (or a person): run a normal search for these words.
        case title(String)
    }

    let endpoint: URL?
    let token: String?
    let session: URLSession
    let timeout: Duration
    private var health: (up: Bool, checked: ContinuousClock.Instant)?

    public init(endpoint: URL?, token: String? = nil, timeout: Duration = .milliseconds(1500),
                configuration: URLSessionConfiguration = .ephemeral) {
        self.endpoint = endpoint
        self.token = token
        self.timeout = timeout
        let config = configuration
        config.timeoutIntervalForRequest = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        session = URLSession(configuration: config)
    }

    /// From Info.plist `BumperSearchEndpoint` (and `BumperSearchToken`), or
    /// `-searchEndpoint <url>` at launch. Neither: on-device only.
    public static func configured(arguments: [String] = ProcessInfo.processInfo.arguments, bundle: Bundle = .main) -> SmartSearch {
        var endpoint = (bundle.object(forInfoDictionaryKey: "BumperSearchEndpoint") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        if let i = arguments.firstIndex(of: "-searchEndpoint"), i + 1 < arguments.count { endpoint = URL(string: arguments[i + 1]) }
        let token = (bundle.object(forInfoDictionaryKey: "BumperSearchToken") as? String).flatMap { $0.isEmpty ? nil : $0 }
        return SmartSearch(endpoint: endpoint, token: token)
    }

    public func understand(_ words: String, in filter: CollectionFilter, genres: [String] = []) async -> Understanding {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intent = await interpret(words) {
            var next = filter
            let changed = next.apply(intent, genres: genres)
            if intent.kind == .title || (changed.isEmpty && next.base == filter.base) { return .title(words) }
            return .filter(next, changed: changed, fromService: true)
        }
        var next = filter
        let changed = next.apply(words: words, genres: genres)
        return changed.isEmpty ? .title(words) : .filter(next, changed: changed, fromService: false)
    }

    /// The service's reading, or nil when it's off, down or slow.
    public func interpret(_ words: String) async -> SearchIntent? {
        guard let endpoint, await isUp() else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONEncoder().encode(["query": words])
        let start = ContinuousClock.now
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                markDown()
                return nil
            }
            let intent = try JSONDecoder().decode(SearchIntent.self, from: data)
            TraceFile.write("search", "“\(words)” → \(intent.kind.rawValue) via \(intent.source ?? "?") in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])))")
            return intent
        } catch {
            TraceFile.write("search", "service failed for “\(words)”: \(error.localizedDescription)")
            markDown()
            return nil
        }
    }

    /// HEAD on the endpoint, remembered for a minute (a failure for 30 s).
    func isUp() async -> Bool {
        if let health, ContinuousClock.now - health.checked < (health.up ? .seconds(60) : .seconds(30)) { return health.up }
        guard let endpoint else { return false }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let up = ((try? await session.data(for: request))?.1 as? HTTPURLResponse)?.statusCode == 204
        health = (up, .now)
        TraceFile.write("search", "service \(up ? "up" : "off") at \(endpoint.host() ?? "?")")
        return up
    }

    private func markDown() { health = (false, .now) }
}
