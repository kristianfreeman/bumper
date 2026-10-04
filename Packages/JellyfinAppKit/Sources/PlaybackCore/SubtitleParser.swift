public import Foundation

public struct TimedCue: Sendable, Equatable {
    public var start: Duration
    public var end: Duration
    public var text: String

    public init(start: Duration, end: Duration, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A parsed text-subtitle track with O(log n) lookup by time.
public struct SubtitleTrack: Sendable {
    public let cues: [TimedCue]

    public init(cues: [TimedCue]) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    /// All cues active at `time`, joined (overlapping cues are legal in SRT/ASS).
    public func text(at time: Duration) -> String? {
        // Binary search for the last cue starting at or before `time`.
        var lo = 0, hi = cues.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= time { lo = mid + 1 } else { hi = mid }
        }
        var active: [String] = []
        var i = lo - 1
        // Walk back over a small window to catch long overlapping cues.
        while i >= 0 && lo - i <= 8 {
            if cues[i].end > time { active.append(cues[i].text) }
            i -= 1
        }
        return active.isEmpty ? nil : active.reversed().joined(separator: "\n")
    }
}

/// SRT, WebVTT and ASS/SSA (styling stripped) parsers.
public enum SubtitleParser {
    public static func parse(_ data: Data, format: String) -> SubtitleTrack {
        let string = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        switch format.lowercased() {
        case "ass", "ssa": return SubtitleTrack(cues: parseASS(string))
        default: return SubtitleTrack(cues: parseSRTorVTT(string))
        }
    }

    static func parseSRTorVTT(_ s: String) -> [TimedCue] {
        var cues: [TimedCue] = []
        for block in s.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "") else { continue }
            let text = lines[(timingIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(TimedCue(start: start, end: end, text: stripTags(text)))
        }
        return cues
    }

    static func parseASS(_ s: String) -> [TimedCue] {
        var cues: [TimedCue] = []
        var format: [String] = []
        for rawLine in s.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Format:"), format.isEmpty || line.contains("Text") {
                format = line.dropFirst(7).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            } else if line.hasPrefix("Dialogue:") {
                let fieldCount = max(format.count, 10)
                let fields = line.dropFirst(9).split(separator: ",", maxSplits: fieldCount - 1, omittingEmptySubsequences: false).map(String.init)
                func field(_ name: String, fallback: Int) -> String? {
                    let idx = format.firstIndex(of: name) ?? fallback
                    return idx < fields.count ? fields[idx] : nil
                }
                guard let start = field("start", fallback: 1).flatMap(parseTimestamp),
                      let end = field("end", fallback: 2).flatMap(parseTimestamp),
                      let raw = field("text", fallback: 9) else { continue }
                let text = stripASS(raw)
                if !text.isEmpty { cues.append(TimedCue(start: start, end: end, text: text)) }
            }
        }
        return cues
    }

    /// Accepts "hh:mm:ss,mmm", "hh:mm:ss.mmm", "mm:ss.mmm", "h:mm:ss.cc".
    static func parseTimestamp(_ raw: String) -> Duration? {
        let t = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = t.split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        let secs = Double(parts.last!) ?? -1
        guard secs >= 0 else { return nil }
        let mins = Double(parts[parts.count - 2]) ?? 0
        let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
        return .milliseconds(Int64(((hours * 60 + mins) * 60 + secs) * 1000))
    }

    static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "{\\\\[^}]*}", with: "", options: .regularExpression)
    }

    /// Drops override blocks ({\an8\i1}…) and converts \N line breaks.
    public static func stripASS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
