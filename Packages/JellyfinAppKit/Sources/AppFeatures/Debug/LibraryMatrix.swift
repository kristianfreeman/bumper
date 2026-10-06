import Foundation
import Instrumentation
import JellyfinAPI
import PlaybackCore

/// One item for each kind of file a library holds — the playback matrix on
/// real files (`-libraryMatrix`; scripts/device-library-matrix.sh plays them
/// in Background, which tells the server nothing).
enum LibraryMatrix {
    struct Pick: Codable {
        var id: String
        var name: String
        var kind: String
        var seconds: Double
        var fps: Double
    }

    /// "mkv · vc1 1080i · AC-3 5.1 · pgssub" — what tells files apart for playback.
    static func kind(_ source: MediaSource) -> String {
        let v = source.videoStream
        let height = v?.height ?? 0
        let size = height >= 2000 ? "2160" : height >= 1000 ? "1080" : height >= 700 ? "720" : "SD"
        let scan = v?.isInterlaced == true ? "i" : "p"
        let range = (v?.videoRangeType).flatMap { $0 == "SDR" ? nil : $0 } ?? ""
        let fps = v.flatMap { $0.realFrameRate ?? $0.averageFrameRate }.map { String(format: "%.3g", $0) } ?? "?"
        let audio = source.audioStreams.first { $0.index == source.defaultAudioStreamIndex } ?? source.audioStreams.first
        let a = [audio?.codec, audio?.profile, audio?.channels.map { "\($0)ch" }].compactMap { $0 }.joined(separator: " ")
        let subs = Set(source.subtitleStreams.compactMap(\.codec)).sorted().joined(separator: "+")
        return [Codecs.split(source.container).first ?? "?", "\(v?.codec ?? "no video") \(size)\(scan)\(fps) \(range)".trimmingCharacters(in: .whitespaces),
                a, subs.isEmpty ? nil : subs].compactMap { $0 }.joined(separator: " · ")
    }

    static func pick(client: JellyfinClient) async {
        // In pages: every item's media details at once timed out on a real library.
        var items: [BaseItem] = []
        var q = ItemQuery(includeItemTypes: [.movie, .episode], limit: 300)
        q.fields = [.mediaSources]
        q.imageTypes = []
        while true {
            do {
                let page = try await client.items(q)
                items += page.items
                if page.items.count < 300 || items.count >= page.totalRecordCount { break }
                q.startIndex += 300
            } catch {
                TraceFile.write("librarymatrix", "couldn't list the library at \(q.startIndex): \(error)")
                if items.isEmpty { return } else { break }
            }
        }
        var seen: [String: Pick] = [:]
        for item in items {
            guard let source = item.mediaSources?.first, item.runTimeTicks ?? 0 > 0 else { continue }
            let k = kind(source)
            if seen[k] == nil {
                let name = [item.seriesName, item.name].compactMap { $0 }.joined(separator: " — ")
                let fps = source.videoStream.flatMap { $0.realFrameRate ?? $0.averageFrameRate } ?? 0
                seen[k] = Pick(id: item.id, name: name, kind: k, seconds: Double(item.runTimeTicks ?? 0) / Double(BaseItem.ticksPerSecond), fps: fps)
            }
        }
        let picks = seen.values.sorted { $0.kind < $1.kind }
        TraceFile.write("librarymatrix", "\(items.count) items, \(picks.count) kinds")
        let url = TraceFile.directory.appending(path: "library-matrix.json")
        try? JSONEncoder().encode(picks).write(to: url)
    }
}
