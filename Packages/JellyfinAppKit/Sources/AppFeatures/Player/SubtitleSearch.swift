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

/// "Find Subtitles": the person's own Jellyfin server searches its subtitle
/// providers (the OpenSubtitles plugin, on the server owner's account — no
/// shared quota), Jev judges which fits this file best, and the server
/// downloads the pick beside the video, so every app sees it from then on.
extension PlayerController {
    func findSubtitles() async {
        guard let plan, let client = app.session?.client else { return }
        subtitleSearch = .searching
        let language = Self.preferredLanguage()
        let candidates: [RemoteSubtitle]
        do {
            candidates = try await client.remoteSubtitles(itemId: plan.item.id, language: language)
        } catch JellyfinError.forbidden {
            subtitleSearch = .failed("Your Jellyfin account isn't allowed to manage subtitles. The server's admin can turn that on in Users.")
            return
        } catch {
            subtitleSearch = .failed("Your server couldn't search for subtitles. Is a subtitle plugin (like OpenSubtitles) installed?")
            return
        }
        guard !candidates.isEmpty else {
            subtitleSearch = .failed("Your server found no \(Self.languageName(language)) subtitles. If it has no subtitle plugin yet, add OpenSubtitles in Jellyfin's dashboard.")
            return
        }
        let (ranked, judgedBy) = await app.subtitleRanker.rank(candidates, for: Self.file(for: plan))
        TraceFile.write("subtitles", "\(candidates.count) found, judged on \(judgedBy); best \(ranked.first?.confidenceText ?? "-")")
        subtitleSearch = .results(Array(ranked.prefix(12)))
    }

    func use(_ found: FoundSubtitle) async {
        guard let plan, let client = app.session?.client else { return }
        let before = Set(plan.mediaSource.subtitleStreams.map(\.index))
        do {
            try await client.downloadRemoteSubtitle(itemId: plan.item.id, subtitleId: found.id)
        } catch JellyfinError.forbidden {
            subtitleSearch = .failed("Your Jellyfin account isn't allowed to add subtitles.")
            return
        } catch {
            subtitleSearch = .failed("The server couldn't download that one.")
            return
        }
        // The server saves it and adds it to the item: wait for the new stream.
        for _ in 0..<12 {
            if let item = try? await client.item(id: plan.item.id),
               let source = item.mediaSources?.first(where: { $0.id == plan.mediaSource.id }) ?? item.mediaSources?.first,
               let added = source.subtitleStreams.first(where: { !before.contains($0.index) }) {
                self.plan?.mediaSource.mediaStreams = source.mediaStreams
                await selectSubtitle(added.index)
                foundSubtitle = found
                TraceFile.write("subtitles", "using \(found.id) (\(found.confidenceText)) as stream \(added.index)")
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        subtitleSearch = .failed("The server downloaded it, but it hasn't shown up yet. Try again in a moment.")
    }

    /// What we know about the file, for judging the fit.
    nonisolated static func file(for plan: PlaybackPlan) -> SubtitleFile {
        let item = plan.item
        let source = plan.mediaSource
        let video = (source.mediaStreams ?? []).first { $0.type == .video }
        return SubtitleFile(
            title: item.seriesName ?? item.name ?? "",
            year: item.productionYear,
            season: item.kind == .episode ? item.parentIndexNumber : nil,
            episode: item.kind == .episode ? item.indexNumber : nil,
            fileName: source.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? source.name,
            fps: video?.realFrameRate ?? video?.averageFrameRate,
            durationSeconds: item.runTimeTicks.map { Double($0) / Double(BaseItem.ticksPerSecond) })
    }

    /// ISO 639-2 ("eng"), from the device's preferred language.
    nonisolated static func preferredLanguage() -> String {
        let code = Locale.preferredLanguages.first.flatMap { Locale.Language(identifier: $0).languageCode } ?? Locale.LanguageCode("en")
        return code.identifier(.alpha3) ?? "eng"
    }

    nonisolated static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? "matching"
    }
}
#endif
