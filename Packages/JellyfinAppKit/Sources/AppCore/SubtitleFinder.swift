public import Foundation
public import JellyfinAPI
import Instrumentation

/// What we know about the file being played (for judging which subtitle fits).
public struct SubtitleFile: Codable, Sendable, Hashable {
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    public var fileName: String?
    public var fps: Double?
    public var durationSeconds: Double?

    public init(title: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil, fileName: String? = nil, fps: Double? = nil, durationSeconds: Double? = nil) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.fileName = fileName
        self.fps = fps
        self.durationSeconds = durationSeconds
    }
}

/// One subtitle the server's providers found, and how surely it fits.
public struct FoundSubtitle: Sendable, Hashable, Identifiable {
    public var remote: RemoteSubtitle
    /// 0…1.
    public var confidence: Double
    public var reasons: [String]
    public var id: String { remote.id }
    public var name: String { remote.name ?? "Subtitle" }

    public init(remote: RemoteSubtitle, confidence: Double, reasons: [String] = []) {
        self.remote = remote
        self.confidence = confidence
        self.reasons = reasons
    }

    /// "92%".
    public var confidenceText: String { "\(Int((confidence * 100).rounded()))%" }
}

/// Puts the server's subtitle candidates in order of fit: Jev's judgement
/// through the search service (services/search, where the Jev key stays),
/// or — when that's off or unreachable — the same heuristic on the device.
public actor SubtitleRanker {
    let base: URL?
    let token: String?
    let session: URLSession
    private var health: (up: Bool, checked: ContinuousClock.Instant)?

    public init(base: URL?, token: String? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        self.base = base
        self.token = token
        configuration.timeoutIntervalForRequest = 4
        session = URLSession(configuration: configuration)
    }

    /// The same service as the search: `…/v1/interpret` → `…/v1/subtitles/rank`.
    public static func configured(arguments: [String] = ProcessInfo.processInfo.arguments, bundle: Bundle = .main) -> SubtitleRanker {
        var endpoint = (bundle.object(forInfoDictionaryKey: "BumperSearchEndpoint") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        if let i = arguments.firstIndex(of: "-searchEndpoint"), i + 1 < arguments.count { endpoint = URL(string: arguments[i + 1]) }
        let token = (bundle.object(forInfoDictionaryKey: "BumperSearchToken") as? String).flatMap { $0.isEmpty ? nil : $0 }
        let base = endpoint.map { $0.deletingLastPathComponent().appending(path: "subtitles/rank") }
        return SubtitleRanker(base: base, token: token)
    }

    /// Best fit first. Never fails: without the service, the heuristic.
    public func rank(_ candidates: [RemoteSubtitle], for file: SubtitleFile) async -> (results: [FoundSubtitle], judgedBy: String) {
        guard !candidates.isEmpty else { return ([], "none") }
        if let remote = await remoteRank(candidates, for: file) { return (remote, "jev") }
        return (SubtitleRanking.rank(candidates, for: file), "device")
    }

    private func remoteRank(_ candidates: [RemoteSubtitle], for file: SubtitleFile) async -> [FoundSubtitle]? {
        guard let base, await isUp() else { return nil }
        struct Candidate: Encodable {
            let id: String, name: String, provider: String?, fps: Double?, downloads: Int?
            let hearingImpaired: Bool?, machineTranslated: Bool?, hashMatch: Bool?
        }
        struct Body: Encodable { let file: SubtitleFile; let candidates: [Candidate] }
        struct Answer: Decodable {
            struct Result: Decodable { let id: String; let confidence: Double; let reasons: [String] }
            let results: [Result]
            let source: String?
        }
        var request = URLRequest(url: base)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONEncoder().encode(Body(file: file, candidates: candidates.prefix(60).map {
            Candidate(id: $0.id, name: $0.name ?? "", provider: $0.providerName, fps: $0.frameRate, downloads: $0.downloadCount,
                      hearingImpaired: $0.hearingImpaired, machineTranslated: ($0.machineTranslated ?? false) || ($0.aiTranslated ?? false),
                      hashMatch: $0.isHashMatch)
        }))
        let start = ContinuousClock.now
        guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else {
            health = (false, .now)
            return nil
        }
        TraceFile.write("subtitles", "ranked \(candidates.count) via \(answer.source ?? "?") in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])))")
        let byId = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return answer.results.compactMap { r in byId[r.id].map { FoundSubtitle(remote: $0, confidence: r.confidence, reasons: r.reasons) } }
    }

    /// HEAD on the endpoint, remembered for a minute (a failure for 30 s).
    private func isUp() async -> Bool {
        if let health, ContinuousClock.now - health.checked < (health.up ? .seconds(60) : .seconds(30)) { return health.up }
        guard let base else { return false }
        var request = URLRequest(url: base)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let up = ((try? await session.data(for: request))?.1 as? HTTPURLResponse)?.statusCode == 204
        health = (up, .now)
        return up
    }
}

/// The judgement without Jev (the service runs the same rules): a hash
/// match is the same file; the file's release group in the subtitle's name
/// is a good sign; a different frame rate won't be in sync; machine
/// translation is a last resort; otherwise, what most people downloaded.
public enum SubtitleRanking {
    public static func rank(_ candidates: [RemoteSubtitle], for file: SubtitleFile) -> [FoundSubtitle] {
        let stem = file.fileName.map { name in
            ["mkv", "mp4", "avi", "m4v", "ts"].reduce(name) { n, ext in n.lowercased().hasSuffix(".\(ext)") ? String(n.dropLast(ext.count + 1)) : n }
        }
        let group = stem?.split(whereSeparator: { "-. ".contains($0) }).last.map { $0.lowercased() }
        let maxDownloads = max(1, candidates.map { $0.downloadCount ?? 0 }.max() ?? 1)
        return candidates.map { c in
            var reasons: [String] = []
            var score = 0.15 + 0.35 * log10(1 + Double(c.downloadCount ?? 0)) / log10(1 + Double(maxDownloads))
            if let group, group.count > 2, (c.name ?? "").lowercased().contains(group) {
                reasons.append("Same release group (\(group.uppercased()))")
                score += 0.3
            }
            if let fps = file.fps, let theirs = c.frameRate, theirs > 0 {
                if abs(fps - theirs) < 0.01 { reasons.append("Frame rate matches") } else {
                    reasons.append("Made for \(theirs.formatted(.number.precision(.fractionLength(0...3)))) fps")
                    score *= 0.35
                }
            }
            if (c.machineTranslated ?? false) || (c.aiTranslated ?? false) { reasons.append("Machine translated"); score *= 0.5 }
            if c.isHashMatch == true { reasons.insert("Made for this exact file", at: 0); score = max(score, 0.97) } else { score = min(score, 0.85) }
            return FoundSubtitle(remote: c, confidence: (score * 100).rounded() / 100, reasons: reasons)
        }
        .sorted { ($0.confidence, $0.remote.downloadCount ?? 0) > ($1.confidence, $1.remote.downloadCount ?? 0) }
    }
}
