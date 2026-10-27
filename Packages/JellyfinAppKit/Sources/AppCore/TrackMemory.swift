public import Foundation
public import JellyfinAPI

/// The subtitles and audio you last chose in a show, for its next episode:
/// Off stays off, English SDH stays English SDH, Japanese audio stays
/// Japanese. Kept by show on this device.
public struct TrackPreference: Codable, Sendable, Equatable {
    /// Subtitles switched off on purpose.
    public var subtitlesOff = false
    public var subtitleLanguage: String?
    /// "text", "styled" (ASS/SSA) or "image" (PGS, VobSub…).
    public var subtitleKind: String?
    public var subtitleSDH = false
    public var subtitleForced = false
    public var audioLanguage: String?

    public init() {}

    static func kind(_ codec: String?) -> String {
        let c = (codec ?? "").lowercased()
        if ["ass", "ssa"].contains(c) { return "styled" }
        if ["pgssub", "pgs", "hdmv_pgs_subtitle", "dvdsub", "dvd_subtitle", "dvbsub", "dvb_subtitle", "xsub"].contains(c) { return "image" }
        return "text"
    }

    static func isSDH(_ s: MediaStream) -> Bool {
        let words = [s.title, s.displayTitle].compactMap { $0 }.joined(separator: " ")
        return words.localizedCaseInsensitiveContains("sdh") || words.localizedCaseInsensitiveContains("hearing")
    }

    /// The subtitle in this episode closest to the one chosen last time:
    /// the same language first, then the same kind, SDH and forced-ness.
    /// nil: none in that language (the setting decides instead).
    public func subtitle(in streams: [MediaStream]) -> Int? {
        guard !subtitlesOff, let language = subtitleLanguage else { return nil }
        let same = streams.filter { ($0.language ?? "").lowercased() == language.lowercased() }
        return same.max { score($0) < score($1) }?.index
    }

    private func score(_ s: MediaStream) -> Int {
        (Self.kind(s.codec) == subtitleKind ? 4 : 0) + (Self.isSDH(s) == subtitleSDH ? 2 : 0) + ((s.isForced == true) == subtitleForced ? 1 : 0)
    }

    /// This episode's audio in the language chosen last time, if it has one.
    public func audio(in streams: [MediaStream]) -> Int? {
        guard let language = audioLanguage else { return nil }
        return streams.first { ($0.language ?? "").lowercased() == language.lowercased() }?.index
    }

    public mutating func remember(subtitle s: MediaStream?) {
        subtitlesOff = s == nil
        subtitleLanguage = s?.language
        subtitleKind = s.map { Self.kind($0.codec) }
        subtitleSDH = s.map(Self.isSDH) ?? false
        subtitleForced = s?.isForced == true
    }
}

/// Track choices by show, in this device's defaults (the most recent 300).
public final class TrackMemory: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "tracks.byShow"
    private static let limit = 300

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private struct Entry: Codable { var preference: TrackPreference; var at: Date }

    private func all() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.key) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    public func preference(forShow id: String) -> TrackPreference? { all()[id]?.preference }

    public func update(show id: String, _ change: (inout TrackPreference) -> Void) {
        var entries = all()
        var preference = entries[id]?.preference ?? TrackPreference()
        change(&preference)
        entries[id] = Entry(preference: preference, at: .now)
        if entries.count > Self.limit {
            for (key, _) in entries.sorted(by: { $0.value.at < $1.value.at }).prefix(entries.count - Self.limit) { entries[key] = nil }
        }
        defaults.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }
}
