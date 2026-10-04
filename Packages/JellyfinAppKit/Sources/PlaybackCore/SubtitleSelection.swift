public import Foundation
public import JellyfinAPI

/// Which subtitle track to turn on when playback starts.
public enum SubtitleSelection {
    /// - Parameters:
    ///   - serverDefault: the track Jellyfin flags as default (honoured first).
    ///   - preferredLanguages: BCP-47 or ISO 639-2 codes, most preferred first
    ///     (the user's Jellyfin setting, then the device languages).
    public static func choose(from streams: [MediaStream], serverDefault: Int?, preferredLanguages: [String]) -> Int? {
        let subs = streams.filter { $0.type == .subtitle }
        guard !subs.isEmpty else { return nil }
        if let serverDefault, subs.contains(where: { $0.index == serverDefault }) { return serverDefault }

        let full = subs.filter { $0.isForced != true }
        let wanted = preferredLanguages.compactMap(alpha3)
        for lang in wanted {
            // A complete track in this language; prefer a plain one over SDH/CC.
            let matches = full.filter { alpha3($0.language ?? "") == lang }
            if let plain = matches.first(where: { !isSDH($0) }) ?? matches.first { return plain.index }
        }
        return (full.first(where: \.isDefaultFlag) ?? full.first ?? subs.first)?.index
    }

    /// "en", "en-US", "eng" → "eng" (Jellyfin reports ISO 639-2).
    static func alpha3(_ code: String) -> String? {
        let base = code.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
        guard !base.isEmpty else { return nil }
        if base.count == 3 { return base }
        return Locale.Language(identifier: base).languageCode?.identifier(.alpha3)
    }

    static func isSDH(_ s: MediaStream) -> Bool {
        let title = (s.title ?? s.displayTitle ?? "").lowercased()
        return title.contains("sdh") || title.contains("hearing") || title.contains("cc")
    }
}

extension MediaStream {
    var isDefaultFlag: Bool { isDefault == true }
}
