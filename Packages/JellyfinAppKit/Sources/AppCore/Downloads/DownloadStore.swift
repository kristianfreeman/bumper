public import Foundation
import Instrumentation
public import JellyfinAPI
public import Observation

/// A downloaded (or downloading) film or episode.
public struct DownloadRecord: Codable, Sendable, Identifiable, Hashable {
    public enum State: Codable, Sendable, Hashable {
        case queued, downloading, paused, finishing, done
        case failed(String)
    }
    public enum Quality: Codable, Sendable, Hashable {
        case original
    }
    /// A piece of the file: its byte range (nil: the whole file, when the
    /// server can't do ranges), and how far it's got.
    public struct Piece: Codable, Sendable, Hashable {
        public var range: ClosedRange<Int64>?
        public var received: Int64 = 0
        public var file: String?               // set once it's complete
        public var resumeData: Data?
        public var length: Int64? { range.map { $0.upperBound - $0.lowerBound + 1 } }
    }

    /// The item's id.
    public var id: String
    /// The item as it was when downloaded (media sources included): enough to
    /// show it and play it with no server.
    public var item: BaseItem
    public var mediaSourceId: String?
    public var accountId: String
    public var quality: Quality
    public var state: State
    /// Bytes in all, when the server said.
    public var size: Int64?
    public var pieces: [Piece]
    /// The finished file, relative to the downloads folder.
    public var file: String?
    public var addedAt: Date
    /// Subtitles saved beside it ("3.vtt" → its file): every text subtitle as
    /// WebVTT (what AVPlayer's overlay reads, which the server extracts when
    /// streaming), external ones also in their own format (for VLCKit).
    public var subtitles: [String: String]?

    public var received: Int64 { pieces.reduce(0) { $0 + ($1.file != nil ? ($1.length ?? $1.received) : $1.received) } }
    public var progress: Double? { size.map { $0 > 0 ? min(1, Double(received) / Double($0)) : 0 } }
    public var isDone: Bool { state == .done }
    public var isActive: Bool { state == .queued || state == .downloading || state == .finishing }
}

/// Every download on this device: films and episodes, kept with the item
/// they were made from so they show and play offline. One item downloads at
/// a time, as several byte-range pieces at once (as fast as the connection
/// goes); the rest wait their turn.
///
/// Files live in Application Support/Downloads (kept, not backed up). The
/// manifest is index.json there; each download's folder also holds its own
/// item.json, so the manifest can be rebuilt from the folders if it's lost.
/// Not on the TV: tvOS keeps no files an app can count on.
@MainActor
@Observable
public final class DownloadStore {
    /// Everything, live (progress included: read it only where progress shows).
    public private(set) var records: [String: DownloadRecord] = [:] { didSet { refreshMarks() } }
    /// Finished downloads' ids, and shows with any — what a card's mark reads.
    /// They change only when a download finishes or goes, not on every byte.
    public private(set) var downloaded: Set<String> = []
    public private(set) var showsWithDownloads: Set<String> = []
    /// iPhone/iPad: whether pieces may come over cellular.
    @ObservationIgnored public var allowsCellular = false

    private func refreshMarks() {
        let done = records.values.filter(\.isDone)
        let ids = Set(done.map(\.id)), shows = Set(done.compactMap(\.item.seriesId))
        if ids != downloaded { downloaded = ids }
        if shows != showsWithDownloads { showsWithDownloads = shows }
    }

    /// How many pieces download at once, and how big each is.
    public static let parallelPieces = 4
    @ObservationIgnored public let pieceSize: Int64

    @ObservationIgnored public let directory: URL
    @ObservationIgnored private let downloader: SegmentedDownloader
    @ObservationIgnored private var clients: [String: JellyfinClient] = [:]
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var lastProgressSave = ContinuousClock.now

    /// - Parameter configuration: the session's (a background one in the
    ///   app on iPhone/iPad; tests inject the mock server through a default one).
    public init(directory: URL? = nil, configuration: URLSessionConfiguration? = nil, pieceSize: Int64 = 32 * 1024 * 1024) {
        self.pieceSize = pieceSize
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Downloads", directoryHint: .isDirectory)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        downloader = SegmentedDownloader(configuration: configuration ?? Self.defaultConfiguration(), piecesDirectory: base.appending(path: ".pieces", directoryHint: .isDirectory))
        if let data = try? Data(contentsOf: base.appending(path: "index.json")),
           let list = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        } else {
            records = Self.rebuild(from: base)
        }
        refreshMarks()
        downloader.setHandler { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    public static let backgroundIdentifier = "com.kristianfreeman.bumper.downloads"

    static func defaultConfiguration() -> URLSessionConfiguration {
        #if os(iOS)
        let c = URLSessionConfiguration.background(withIdentifier: backgroundIdentifier)
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        return c
        #else
        return .default
        #endif
    }

    /// The system's handler for a background session's events (iOS).
    public func handleBackgroundEvents(_ completion: @escaping @Sendable () -> Void) {
        downloader.setBackgroundCompletion(completion)
    }

    // MARK: Asking

    public func record(_ itemId: String) -> DownloadRecord? { records[itemId] }

    /// The finished file for an item, if it's downloaded.
    public func localFile(for itemId: String) -> URL? {
        guard let r = records[itemId], r.isDone, let file = r.file else { return nil }
        let url = directory.appending(path: file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A saved subtitle for a stream, in a format ("vtt", "srt", …).
    public func subtitleFile(itemId: String, index: Int, format: String) -> URL? {
        guard let path = records[itemId]?.subtitles?["\(index).\(format)"] else { return nil }
        return directory.appending(path: path)
    }

    /// Downloaded episodes of a series (or of one season).
    public func episodes(seriesId: String, seasonId: String? = nil) -> [DownloadRecord] {
        records.values.filter { $0.item.seriesId == seriesId && (seasonId == nil || $0.item.seasonId == seasonId) }
            .sorted { ($0.item.parentIndexNumber ?? 0, $0.item.indexNumber ?? 0) < ($1.item.parentIndexNumber ?? 0, $1.item.indexNumber ?? 0) }
    }

    /// A show's downloads at a glance: how many episodes, how many done.
    public func summary(seriesId: String, seasonId: String? = nil) -> (total: Int, done: Int, active: Int) {
        let eps = records.values.filter { $0.item.seriesId == seriesId && (seasonId == nil || $0.item.seasonId == seasonId) }
        return (eps.count, eps.filter(\.isDone).count, eps.filter(\.isActive).count)
    }

    /// Space left on the device for downloads.
    public var freeBytes: Int64? {
        #if os(tvOS)
        nil                                                       // no downloads there
        #else
        (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        #endif
    }

    /// Bytes on disk (finished files and pieces so far).
    public var bytesUsed: Int64 { records.values.reduce(0) { $0 + ($1.isDone ? ($1.size ?? $1.received) : $1.received) } }

    // MARK: Downloading

    /// Downloads films and episodes (a series or season: pass its episodes).
    public func download(_ items: [BaseItem], client: JellyfinClient, accountId: String) {
        clients[accountId] = client
        for item in items where records[item.id] == nil && item.kind.isPlayable {
            records[item.id] = DownloadRecord(id: item.id, item: item, mediaSourceId: item.mediaSources?.first?.id, accountId: accountId,
                                              quality: .original, state: .queued, size: nil, pieces: [], file: nil, addedAt: .now)
        }
        save()
        for item in items { if let r = records[item.id] { writeItemManifest(r) } }
        Task { await advance() }
    }

    /// The client to use for an account's downloads (after a relaunch).
    public func use(_ client: JellyfinClient, for accountId: String) {
        clients[accountId] = client
        Task { await resumeAfterLaunch() }
    }

    public func pause(_ itemId: String) {
        guard var r = records[itemId], r.isActive else { return }
        r.state = .paused
        records[itemId] = r
        save()
        Task { await downloader.cancel(download: itemId, keepResumeData: true); await advance() }
    }

    public func resume(_ itemId: String) {
        guard var r = records[itemId], r.state == .paused || isFailed(r) else { return }
        r.state = .queued
        records[itemId] = r
        save()
        Task { await advance() }
    }

    /// Removes downloads (and their files): films, episodes, a season, a show.
    public func remove(_ itemIds: [String]) {
        for id in itemIds {
            guard let r = records.removeValue(forKey: id) else { continue }
            Task { await downloader.cancel(download: id, keepResumeData: false) }
            if let file = r.file { try? FileManager.default.removeItem(at: directory.appending(path: file)) }
            for p in r.pieces { if let f = p.file { try? FileManager.default.removeItem(at: directory.appending(path: f)) } }
            try? FileManager.default.removeItem(at: directory.appending(path: id, directoryHint: .isDirectory))
        }
        save()
        Task { await advance() }
    }

    public func removeSeries(_ seriesId: String, seasonId: String? = nil) {
        remove(episodes(seriesId: seriesId, seasonId: seasonId).map(\.id))
    }

    private func isFailed(_ r: DownloadRecord) -> Bool { if case .failed = r.state { return true } else { return false } }

    /// Starts the next queued download when nothing is downloading.
    private func advance() async {
        guard !records.values.contains(where: { $0.state == .downloading || $0.state == .finishing }) else { return }
        guard let next = records.values.filter({ $0.state == .queued }).min(by: { $0.addedAt < $1.addedAt }) else { return }
        await start(next.id)
    }

    private func start(_ id: String) async {
        guard var r = records[id], let client = clients[r.accountId] else { return }
        r.state = .downloading
        records[id] = r
        let url = client.downloadURL(itemId: id)
        if r.item.mediaSources?.isEmpty ?? true, let full = try? await client.item(id: id) {
            // A card's item has no media sources: the snapshot needs them to play offline.
            r.item = full
            r.mediaSourceId = full.mediaSources?.first?.id
            records[id]?.item = full
            records[id]?.mediaSourceId = r.mediaSourceId
        }
        if r.pieces.isEmpty {
            // How big, and can it come in pieces?
            var head = URLRequest(url: url)
            head.httpMethod = "HEAD"
            let response = (try? await client.session.data(for: head))?.1 as? HTTPURLResponse
            let size = response?.expectedContentLength ?? -1
            let ranges = response?.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") ?? false
            guard var current = records[id], current.state == .downloading else { return }
            current.size = size > 0 ? size : (current.item.mediaSources?.first?.size)
            current.pieces = Self.pieces(size: size > 0 ? size : nil, ranges: ranges, pieceSize: pieceSize)
            current.file = "\(id)/\(Self.fileName(for: current.item, response: response))"
            r = current
            records[id] = r
            TraceFile.write("downloads", "\(r.item.name ?? id): \(r.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "size unknown"), \(r.pieces.count) piece(s)")
        }
        save()
        fill(id, url: url)
        if records[id]?.subtitles == nil { Task { await fetchSubtitles(id, client: client) } }
    }

    /// The item's subtitles, small enough to fetch whole beside the pieces.
    private func fetchSubtitles(_ id: String, client: JellyfinClient) async {
        guard let r = records[id], let source = r.item.mediaSources?.first(where: { $0.id == r.mediaSourceId }) ?? r.item.mediaSources?.first else { return }
        var saved: [String: String] = [:]
        let folder = directory.appending(path: id, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for stream in source.subtitleStreams where stream.isTextSubtitleStream == true || stream.isExternal == true {
            var formats: [String] = stream.isTextSubtitleStream == true ? ["vtt"] : []
            if stream.isExternal == true { formats.append(Self.subtitleExtension(stream.codec)) }
            for format in Set(formats) {
                let url = client.subtitleURL(itemId: id, mediaSourceId: source.id, streamIndex: stream.index, format: format)
                guard let (data, response) = try? await client.session.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { continue }
                let name = "subtitle-\(stream.index).\(format)"
                if (try? data.write(to: folder.appending(path: name), options: .atomic)) != nil { saved["\(stream.index).\(format)"] = "\(id)/\(name)" }
            }
        }
        guard records[id] != nil else { return }
        records[id]?.subtitles = saved
        save()
        if saved.count > 0 { TraceFile.write("downloads", "\(r.item.name ?? id): \(saved.count) subtitle file(s)") }
    }

    /// A subtitle codec's file extension (as the player asks for it).
    public static func subtitleExtension(_ codec: String?) -> String {
        switch (codec ?? "").lowercased() {
        case "subrip", "srt": "srt"
        case "ass": "ass"
        case "ssa": "ssa"
        case "webvtt", "vtt": "vtt"
        case "pgssub": "sup"
        default: "srt"
        }
    }

    /// Keeps `parallelPieces` pieces of a download in flight.
    private func fill(_ id: String, url: URL) {
        guard let r = records[id], r.state == .downloading else { return }
        let inFlight = inFlightPieces[id] ?? []
        let waiting = r.pieces.indices.filter { r.pieces[$0].file == nil && !inFlight.contains($0) }
        for i in waiting.prefix(max(0, Self.parallelPieces - inFlight.count)) {
            inFlightPieces[id, default: []].insert(i)
            let resume = r.pieces[i].resumeData
            records[id]?.pieces[i].resumeData = nil
            downloader.fetch(url, range: r.pieces[i].range, download: id, piece: i, resumeData: resume, allowsCellular: allowsCellular)
        }
    }

    @ObservationIgnored private var inFlightPieces: [String: Set<Int>] = [:]
    @ObservationIgnored private var liveReceived: [String: [Int: Int64]] = [:]
    @ObservationIgnored private var lastPublish: [String: ContinuousClock.Instant] = [:]

    private func handle(_ event: SegmentedDownloader.Event) {
        switch event {
        case .progress(let id, let piece, let received):
            // Held here, shown a few times a second (every byte redrew the page).
            liveReceived[id, default: [:]][piece] = received
            if ContinuousClock.now - (lastPublish[id] ?? .now - .seconds(1)) >= .milliseconds(250) {
                lastPublish[id] = .now
                guard var r = records[id] else { return }
                for (p, bytes) in liveReceived[id] ?? [:] where r.pieces.indices.contains(p) && r.pieces[p].file == nil { r.pieces[p].received = bytes }
                records[id] = r
            }
            if ContinuousClock.now - lastProgressSave > .seconds(5) { lastProgressSave = .now; save() }
        case .finished(let id, let piece, let file):
            inFlightPieces[id]?.remove(piece)
            guard var r = records[id], r.pieces.indices.contains(piece) else { try? FileManager.default.removeItem(at: file); return }
            let folder = directory.appending(path: id, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let kept = folder.appending(path: "piece-\(piece)")
            try? FileManager.default.removeItem(at: kept)
            try? FileManager.default.moveItem(at: file, to: kept)
            r.pieces[piece].file = "\(id)/piece-\(piece)"
            r.pieces[piece].received = r.pieces[piece].length ?? ((try? kept.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0)
            records[id] = r
            if r.pieces.allSatisfy({ $0.file != nil }) {
                Task { await finish(id) }
            } else if let client = clients[r.accountId] {
                fill(id, url: client.downloadURL(itemId: id))
            }
            save()
        case .failed(let id, let piece, let resumeData, let message):
            inFlightPieces[id]?.remove(piece)
            guard var r = records[id], r.pieces.indices.contains(piece) else { return }
            r.pieces[piece].resumeData = resumeData
            if r.state == .downloading {
                // A pause cancels its pieces too: only a real failure stops it.
                r.state = .failed(message)
                records[id] = r
                Task { await downloader.cancel(download: id, keepResumeData: true); await advance() }
            } else {
                records[id] = r
            }
            save()
        }
    }

    /// Joins the pieces into the file, in order.
    private func finish(_ id: String) async {
        guard var r = records[id], let file = r.file else { return }
        r.state = .finishing
        records[id] = r
        let base = directory
        let parts = r.pieces.compactMap(\.file)
        let joined: Bool = await Task.detached(priority: .utility) {
            let target = base.appending(path: file)
            try? FileManager.default.removeItem(at: target)
            guard FileManager.default.createFile(atPath: target.path, contents: nil), let out = try? FileHandle(forWritingTo: target) else { return false }
            defer { try? out.close() }
            for part in parts {
                let url = base.appending(path: part)
                guard let input = try? FileHandle(forReadingFrom: url) else { return false }
                while let chunk = try? input.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty { try? out.write(contentsOf: chunk) }
                try? input.close()
                try? FileManager.default.removeItem(at: url)
            }
            return true
        }.value
        guard var done = records[id] else { return }
        if joined {
            done.state = .done
            done.size = (try? base.appending(path: file).resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? done.size
            done.pieces = done.pieces.map { var p = $0; p.file = nil; p.resumeData = nil; p.received = p.length ?? p.received; return p }
            TraceFile.write("downloads", "\(done.item.name ?? id) downloaded")
            writeItemManifest(done)
        } else {
            done.state = .failed("Couldn't put the file together.")
        }
        records[id] = done
        save()
        await advance()
    }

    /// After a relaunch: pieces the system finished or carried on are picked
    /// up; the rest start again from their resume data.
    private func resumeAfterLaunch() async {
        let running = Set(await downloader.running().map { "\($0.download)|\($0.piece)" })
        for (id, r) in records where r.state == .downloading || r.state == .finishing {
            if r.pieces.allSatisfy({ $0.file != nil }) { await finish(id); continue }
            inFlightPieces[id] = Set(r.pieces.indices.filter { running.contains("\(id)|\($0)") })
            if let client = clients[r.accountId] { fill(id, url: client.downloadURL(itemId: id)) }
        }
        await advance()
    }

    // MARK: Pieces

    static func pieces(size: Int64?, ranges: Bool, pieceSize: Int64) -> [DownloadRecord.Piece] {
        guard let size, ranges, size > pieceSize else {
            return [DownloadRecord.Piece(range: size.map { 0...($0 - 1) }.flatMap { ranges ? $0 : nil })]
        }
        return stride(from: Int64(0), to: size, by: Int(pieceSize)).map { start in
            DownloadRecord.Piece(range: start...min(size - 1, start + pieceSize - 1))
        }
    }

    /// "media.mkv": the server's own name for the file's kind.
    static func fileName(for item: BaseItem, response: HTTPURLResponse?) -> String {
        let fromHeader = response?.value(forHTTPHeaderField: "Content-Disposition").flatMap { header in
            header.range(of: #"filename="?[^";]+"?"#, options: .regularExpression).map { String(header[$0]) }
        }.map { URL(fileURLWithPath: $0.replacingOccurrences(of: "filename=", with: "").replacingOccurrences(of: "\"", with: "")).pathExtension }
        let fromPath = item.mediaSources?.first?.path.map { URL(fileURLWithPath: $0).pathExtension }
        let ext = [fromHeader, fromPath, item.mediaSources?.first?.container?.split(separator: ",").first.map(String.init)]
            .compactMap { $0 }.first { !$0.isEmpty } ?? "mkv"
        return "media.\(ext.lowercased())"
    }

    /// The download's own copy of its record, beside its file.
    private func writeItemManifest(_ r: DownloadRecord) {
        let folder = directory.appending(path: r.id, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(r).write(to: folder.appending(path: "item.json"), options: .atomic)
    }

    /// The manifest from each download's own item.json (index.json missing
    /// or unreadable).
    static func rebuild(from base: URL) -> [String: DownloadRecord] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        let found = folders.compactMap { folder -> DownloadRecord? in
            guard let data = try? Data(contentsOf: folder.appending(path: "item.json")),
                  var r = try? JSONDecoder().decode(DownloadRecord.self, from: data) else { return nil }
            // Done only if its file is really there; anything else starts over.
            if !(r.isDone && r.file.map { FileManager.default.fileExists(atPath: base.appending(path: $0).path) } == true) {
                r.state = .paused
                r.pieces = []
            }
            return r
        }
        if !found.isEmpty { TraceFile.write("downloads", "rebuilt the manifest from \(found.count) folder(s)") }
        return Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func save() {
        saving?.cancel()
        let list = Array(records.values)
        let url = directory.appending(path: "index.json")
        saving = Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(list) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
