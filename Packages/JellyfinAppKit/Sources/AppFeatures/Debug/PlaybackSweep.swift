import Foundation
import Instrumentation
import JellyfinAPI
import PlaybackCore

/// Every kind of file in the library, played in turn in one launch
/// (`-sweep`; scripts/device-sweep.sh). A few seconds each from a little way
/// in, as a quiet Background play: the server is told nothing, nothing shows
/// in Now Playing, nothing is remembered for the show. One `[sweep]` line a
/// file — played, failed, stalled or never started — and sweep.json at the end.
@MainActor
enum PlaybackSweep {
    /// The quiet play's player, as soon as it's made (failures included:
    /// `app.player` only follows one that got going).
    static weak var current: PlayerController?

    struct Result: Codable {
        var index: Int
        var id: String
        var name: String
        var kind: String
        var outcome: String
        var detail: String
    }

    static func run(app: AppModel, client: JellyfinClient) async {
        let options = app.options
        // The script's list (sweep-picks.json, copied over), else the library's own pick.
        let listed = TraceFile.directory.appending(path: "sweep-picks.json")
        var picks = (try? Data(contentsOf: listed)).flatMap { try? JSONDecoder().decode([LibraryMatrix.Pick].self, from: $0) } ?? []
        if picks.isEmpty { picks = await LibraryMatrix.pick(client: client) }
        TraceFile.write("sweep", "\(picks.count) files, \(Int(options.sweepSeconds)) s each\(options.sweepSubtitles ? ", subtitles on" : "")")
        var results: [Result] = []
        for (i, pick) in picks.enumerated() where i >= options.sweepFrom {
            let (outcome, detail) = await play(pick, app: app, client: client, seconds: options.sweepSeconds, subtitles: options.sweepSubtitles, at: options.sweepAt)
            results.append(Result(index: i, id: pick.id, name: pick.name, kind: pick.kind, outcome: outcome, detail: detail))
            TraceFile.write("sweep", "\(i + 1)/\(picks.count) \(outcome) — \(pick.kind) — \(pick.name) — \(detail)")
            try? JSONEncoder().encode(results).write(to: TraceFile.directory.appending(path: "sweep.json"))
        }
        app.playback = nil
        let played = results.filter { $0.outcome == "PLAYED" }.count
        TraceFile.write("sweep", "done: \(played) played, \(results.count - played) didn't")
    }

    private static func play(_ pick: LibraryMatrix.Pick, app: AppModel, client: JellyfinClient, seconds: Double, subtitles: Bool, at: Double?) async -> (String, String) {
        var item: BaseItem
        do { item = try await client.item(id: pick.id) } catch { return ("NO ITEM", "\(error)") }
        if item.userData == nil { item.userData = UserItemData() }
        item.userData?.playbackPositionTicks = Duration.seconds(at.map { pick.seconds * $0 } ?? min(120, pick.seconds * 0.3)).ticks
        // The hardest subtitle the file has: styled, then pictures, then text.
        let subtitle = subtitles ? item.mediaSources?.first.flatMap { source in
            let rank = { (s: MediaStream) -> Int in
                let c = (s.codec ?? "").lowercased()
                return ["ass", "ssa"].contains(c) ? 0 : ["pgssub", "dvdsub", "dvd_subtitle", "hdmv_pgs_subtitle", "dvbsub"].contains(c) ? 1 : 2
            }
            return source.subtitleStreams.min { rank($0) < rank($1) }?.index
        } : nil

        let request = PlaybackRequest(item: item, resume: true, subtitleIndex: subtitle ?? -1, background: true, quiet: true)
        let opened = ContinuousClock.now
        app.playback = request
        defer { current = nil }

        // Open → the playhead really moving (AVPlayer says it's moving a
        // second or more before its first frame), or a failure, or nothing within 25 s.
        var player: PlayerController?
        var from: Duration?
        var moving = false
        while opened.duration(to: .now) < .seconds(25) {
            try? await Task.sleep(for: .milliseconds(100))
            guard let p = current, p.request.id == request.id else { continue }
            player = p
            if case .failed(let message) = p.phase { await p.stop(); return ("FAILED", message) }
            guard p.phase == .playing, !p.isStarting, let engine = p.engine else { continue }
            if let from, engine.playheadNow - from >= .milliseconds(300) { moving = true; break }
            if from == nil { from = engine.playheadNow }
        }
        guard let player, moving, let first = player.engine else {
            await player?.stop()
            return (player == nil ? "NO PLAYER" : "TIMEOUT", "not moving after 25 s")
        }
        let startup = Int(opened.duration(to: .now).milliseconds)
        let t0 = first.playheadNow, d0 = first.stats.decodedFrames, l0 = first.stats.droppedFrames
        try? await Task.sleep(for: .seconds(seconds))

        if case .failed(let message) = player.phase { await player.stop(); return ("FAILED", message) }
        guard let engine = player.engine else { await player.stop(); return ("FAILED", "no engine") }
        let how = player.plan.map { "\($0.engine.rawValue) \($0.method.rawValue)" } ?? "?"
        // A switch mid-measure (AVPlayer giving up for VLCKit) has nothing to compare: it started, then changed.
        if engine !== first { await player.stop(); return ("SWITCHED", "\(startup) ms to play, then \(how) took over") }
        let moved = (engine.playheadNow - t0).seconds
        let decoded = engine.stats.decodedFrames - d0
        let dropped = engine.stats.droppedFrames - l0
        // The subtitle asked for, read back: VLCKit's own drawing, or the app's text overlay.
        var drawn: String?
        if let subtitle {
            let showing = engine.rendersSubtitles && player.subtitleTrack == nil ? engine.drawnSubtitleStream : (player.subtitleTrack != nil ? player.selectedSubtitle : nil)
            let codec = item.mediaSources?.first?.subtitleStreams.first { $0.index == subtitle }?.codec ?? "?"
            drawn = showing == subtitle ? " · subtitle \(codec) #\(subtitle) on" : " · subtitle \(codec) #\(subtitle) asked, \(showing.map { "#\($0)" } ?? "none") drawn"
            if player.plainSubtitles { drawn! += " (plain: memory ran low)" }
        }
        await player.stop()
        var outcome = moved >= seconds * 0.5 ? "PLAYED" : "STALLED"
        if outcome == "PLAYED", let drawn, drawn.contains("asked") { outcome = "NO SUBTITLE" }
        return (outcome, "\(how) · \(startup) ms to play · \(String(format: "%.1f", moved)) s in \(Int(seconds)) s · \(decoded) decoded, \(dropped) dropped\(drawn ?? "")")
    }
}
