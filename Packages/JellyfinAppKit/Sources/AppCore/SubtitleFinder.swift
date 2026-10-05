public import Foundation
import Instrumentation

/// What the subtitle search knows about the file being played.
public struct SubtitleQuery: Codable, Sendable, Hashable {
    public var imdbId: String?
    public var tmdbId: String?
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    public var languages: [String]
    public var fileName: String?
    public var fps: Double?
    public var durationSeconds: Double?
    public var moviehash: String?

    public init(imdbId: String? = nil, tmdbId: String? = nil, title: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil,
                languages: [String], fileName: String? = nil, fps: Double? = nil, durationSeconds: Double? = nil, moviehash: String? = nil) {
        self.imdbId = imdbId
        self.tmdbId = tmdbId
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.languages = languages
        self.fileName = fileName
        self.fps = fps
        self.durationSeconds = durationSeconds
        self.moviehash = moviehash
    }
}

/// One subtitle the service found, with how surely it fits this file.
public struct FoundSubtitle: Codable, Sendable, Hashable, Identifiable {
    public var fileId: Int
    public var language: String
    public var release: String
    public var fps: Double?
    public var downloads: Int
    public var hearingImpaired: Bool
    public var machineTranslated: Bool
    public var hashMatch: Bool
    /// 0…1.
    public var confidence: Double
    public var reasons: [String]
    public var id: Int { fileId }

    public init(fileId: Int, language: String, release: String, fps: Double? = nil, downloads: Int = 0, hearingImpaired: Bool = false,
                machineTranslated: Bool = false, hashMatch: Bool = false, confidence: Double, reasons: [String] = []) {
        self.fileId = fileId
        self.language = language
        self.release = release
        self.fps = fps
        self.downloads = downloads
        self.hearingImpaired = hearingImpaired
        self.machineTranslated = machineTranslated
        self.hashMatch = hashMatch
        self.confidence = confidence
        self.reasons = reasons
    }

    /// "92%".
    public var confidenceText: String { "\(Int((confidence * 100).rounded()))%" }
}

/// Subtitles from the search service (services/search: OpenSubtitles,
/// judged by Jev, kept in Workers KV). Off when the service isn't set up.
public actor SubtitleFinder {
    let base: URL?
    let token: String?
    let session: URLSession
    private var health: (up: Bool, checked: ContinuousClock.Instant)?

    public init(base: URL?, token: String? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        self.base = base
        self.token = token
        configuration.timeoutIntervalForRequest = 12           // OpenSubtitles + Jev on a miss
        session = URLSession(configuration: configuration)
    }

    /// The same service as the search: `…/v1/interpret` → `…/v1/subtitles/`.
    public static func configured(arguments: [String] = ProcessInfo.processInfo.arguments, bundle: Bundle = .main) -> SubtitleFinder {
        var endpoint = (bundle.object(forInfoDictionaryKey: "BumperSearchEndpoint") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        if let i = arguments.firstIndex(of: "-searchEndpoint"), i + 1 < arguments.count { endpoint = URL(string: arguments[i + 1]) }
        let token = (bundle.object(forInfoDictionaryKey: "BumperSearchToken") as? String).flatMap { $0.isEmpty ? nil : $0 }
        let base = endpoint.map { $0.deletingLastPathComponent().appending(path: "subtitles", directoryHint: .isDirectory) }
        return SubtitleFinder(base: base, token: token)
    }

    public func isAvailable() async -> Bool {
        if let health, ContinuousClock.now - health.checked < .seconds(60) { return health.up }
        guard let base else { return false }
        var request = URLRequest(url: base.appending(path: "search"))
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        authorize(&request)
        let up = ((try? await session.data(for: request))?.1 as? HTTPURLResponse)?.statusCode == 204
        health = (up, .now)
        return up
    }

    public func search(_ query: SubtitleQuery) async throws -> [FoundSubtitle] {
        guard let base else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: base.appending(path: "search"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(query)
        authorize(&request)
        let start = ContinuousClock.now
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Body: Decodable { var results: [FoundSubtitle]; var source: String? }
        let body = try JSONDecoder().decode(Body.self, from: data)
        TraceFile.write("subtitles", "search “\(query.title)” → \(body.results.count) via \(body.source ?? "?") in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])))")
        return body.results
    }

    public func download(_ fileId: Int) async throws -> Data {
        guard let base else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: base.appending(path: "download"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["fileId": fileId])
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { throw URLError(.badServerResponse) }
        return data
    }

    private func authorize(_ request: inout URLRequest) {
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }
}

/// OpenSubtitles' file hash: the size plus the first and last 64 KB read
/// as little-endian 64-bit words, summed with overflow. Identifies the
/// exact file, so a subtitle made for it is a sure match.
public enum OpenSubtitlesHash {
    public static let chunk = 65_536

    public static func compute(size: Int64, head: Data, tail: Data) -> String? {
        guard head.count >= chunk, tail.count >= chunk else { return nil }
        var hash = UInt64(bitPattern: size)
        for data in [head.prefix(chunk), tail.suffix(chunk)] {
            let bytes = [UInt8](data)
            var i = 0
            while i + 8 <= bytes.count {
                var word: UInt64 = 0
                for b in 0..<8 { word |= UInt64(bytes[i + b]) << (8 * UInt64(b)) }
                hash = hash &+ word
                i += 8
            }
        }
        return String(format: "%016llx", hash)
    }
}
