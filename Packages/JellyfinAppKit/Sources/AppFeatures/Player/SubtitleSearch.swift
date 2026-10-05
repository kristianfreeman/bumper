#if os(tvOS)
import AppCore
import Foundation
import Instrumentation
import JellyfinAPI
import PlaybackCore

enum SubtitleSearchState: Equatable {
    case idle, searching
    case results([FoundSubtitle])
    case failed(String)
}

/// "Find Subtitles": ask the search service for subtitles that fit this
/// file, use one at once, and save it on the server so it's there next time
/// (on every device). If the server won't take it, it stays on this TV.
extension PlayerController {
    func findSubtitles() async {
        guard let plan, let client = app.session?.client else { return }
        subtitleSearch = .searching
        guard await app.subtitleFinder.isAvailable() else {
            subtitleSearch = .failed("Subtitle search isn't set up on this Bumper yet.")
            return
        }
        let query = await Self.query(for: plan, client: client)
        do {
            let found = try await app.subtitleFinder.search(query)
            subtitleSearch = found.isEmpty ? .failed("Nothing found in \(Self.languageName(query.languages.first)).") : .results(Array(found.prefix(12)))
        } catch {
            subtitleSearch = .failed("Couldn't search just now.")
        }
    }

    func use(_ found: FoundSubtitle) async {
        guard let plan, let client = app.session?.client else { return }
        do {
            let data = try await app.subtitleFinder.download(found.fileId)
            let file = try SubtitleFiles.save(data, itemId: plan.item.id, fileId: found.fileId)
            selectedSubtitle = nil
            subtitleTrack = nil
            subtitleText = nil
            foundSubtitle = found
            if let engine, engine.rendersSubtitles {
                await engine.selectSubtitle(MediaStream(index: -1_000 - found.fileId % 1_000, type: .subtitle, codec: "subrip"), external: file)
            } else {
                subtitleTrack = SubtitleParser.parse(data, format: "srt")
            }
            TraceFile.write("subtitles", "using \(found.fileId) (\(found.confidenceText)) for \(plan.item.id)")
            // Keep it: on the server when allowed (every app sees it), here regardless.
            Task.detached {
                do {
                    try await client.uploadSubtitle(itemId: plan.item.id, language: Self.alpha3(found.language), format: "srt",
                                                    data: data, hearingImpaired: found.hearingImpaired)
                    TraceFile.write("subtitles", "saved on the server")
                } catch {
                    TraceFile.write("subtitles", "server didn't take it (\(error)); kept on this TV")
                }
            }
        } catch {
            subtitleSearch = .failed("Couldn't download that one.")
        }
    }

    /// What we know about the file: ids, episode, frame rate, length, name,
    /// and (when the server allows range reads) its OpenSubtitles hash.
    nonisolated static func query(for plan: PlaybackPlan, client: JellyfinClient) async -> SubtitleQuery {
        let item = plan.item
        let source = plan.mediaSource
        var ids = item.providerIds ?? [:]
        if item.kind == .episode, let seriesId = item.seriesId, let series = try? await client.item(id: seriesId) {
            ids = series.providerIds ?? ids
        }
        let video = (source.mediaStreams ?? []).first { $0.type == .video }
        let language = Locale.preferredLanguages.first.flatMap { Locale.Language(identifier: $0).languageCode?.identifier } ?? "en"
        var hash: String?
        if let size = source.size, size > Int64(OpenSubtitlesHash.chunk * 2) {
            async let head = client.fileBytes(itemId: item.id, mediaSourceId: source.id, container: source.container, from: 0, count: OpenSubtitlesHash.chunk)
            async let tail = client.fileBytes(itemId: item.id, mediaSourceId: source.id, container: source.container, from: size - Int64(OpenSubtitlesHash.chunk), count: OpenSubtitlesHash.chunk)
            if let head = try? await head, let tail = try? await tail { hash = OpenSubtitlesHash.compute(size: size, head: head, tail: tail) }
        }
        return SubtitleQuery(
            imdbId: ids["Imdb"], tmdbId: ids["Tmdb"],
            title: item.seriesName ?? item.name ?? "",
            year: item.productionYear,
            season: item.kind == .episode ? item.parentIndexNumber : nil,
            episode: item.kind == .episode ? item.indexNumber : nil,
            languages: [language],
            fileName: source.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? source.name,
            fps: video?.realFrameRate ?? video?.averageFrameRate,
            durationSeconds: item.runTimeTicks.map { Double($0) / Double(BaseItem.ticksPerSecond) },
            moviehash: hash)
    }

    nonisolated static func alpha3(_ code: String) -> String {
        Locale.Language(identifier: code).languageCode?.identifier(.alpha3) ?? code
    }

    nonisolated static func languageName(_ code: String?) -> String {
        code.flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? "your language"
    }
}

/// Downloaded subtitles, kept per item on this TV.
enum SubtitleFiles {
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Subtitles", directoryHint: .isDirectory)
    }

    static func save(_ data: Data, itemId: String, fileId: Int) throws -> URL {
        let dir = directory.appending(path: itemId, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "\(fileId).srt")
        try data.write(to: url, options: .atomic)
        return url
    }
}
#endif
