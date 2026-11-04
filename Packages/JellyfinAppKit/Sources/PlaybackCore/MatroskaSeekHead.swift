public import Foundation

/// The fix for MKVs VLCKit can't seek in.
///
/// VLCKit reads what an MKV's SeekHead points at in the order it lists them,
/// and reads the Cues (the seek index) the moment it gets to them. Listed
/// before the Tracks, every cue is for a track it doesn't know yet, and it
/// throws them all away: a seek then decodes from the first frame. Dark City
/// (mkvmerge 7.1, 2014) couldn't resume at 2 min; Amélie not at 30; about
/// 7% of one library's MKVs, older mkvmerge and some others.
///
/// The fix moves Info and Tracks to the front of the SeekHead's list. Each
/// entry keeps its own bytes and the list its length, so nothing else in the
/// file moves: the same bytes, served in a different order.
public enum MatroskaSeekHead {
    /// What to serve instead: `bytes` in place of the file's bytes at `range`.
    public struct Fix: Sendable, Equatable {
        public var range: Range<Int>
        public var bytes: Data
    }

    /// How much of the start of a file `fix(head:)` wants: the SeekHead is
    /// the Segment's first child (mkvmerge, FFmpeg, MakeMKV all put it there).
    public static let headLength = 4096

    /// The fix for this file, from its first bytes; nil when it needs none
    /// (Tracks before Cues already, no Cues listed, not an MKV) or the start
    /// isn't laid out as expected.
    public static func fix(head: Data) -> Fix? {
        let b = [UInt8](head)
        var reader = Reader(bytes: b)
        // EBML header, then the Segment (its size is the whole file: skip only its header).
        guard let ebml = reader.element(at: 0), ebml.id == 0x1A45_DFA3,
              let segment = reader.element(at: ebml.end), segment.id == 0x1853_8067 else { return nil }
        // The SeekHead, possibly after a Void.
        var at = segment.body
        var seekHead: Element?
        while let el = reader.element(at: at), el.end <= b.count {
            if el.id == 0x114D_9B74 { seekHead = el; break }
            guard el.id == 0xEC || el.id == 0xBF else { return nil }        // only Void/CRC-32 may come first
            at = el.end
        }
        guard let seekHead else { return nil }

        // Its children: Seek entries (and CRC-32 / Void).
        var children: [(element: Element, target: UInt32?)] = []
        at = seekHead.body
        while at < seekHead.end {
            guard let el = reader.element(at: at), el.end <= seekHead.end else { return nil }
            children.append((el, el.id == 0x4DBB ? reader.seekTarget(of: el) : nil))
            at = el.end
        }
        let cues: UInt32 = 0x1C53_BB6B, tracks: UInt32 = 0x1654_AE6B, info: UInt32 = 0x1549_A966
        guard let cuesAt = children.firstIndex(where: { $0.target == cues }),
              let tracksAt = children.firstIndex(where: { $0.target == tracks }),
              tracksAt > cuesAt else { return nil }

        // Info (the timescale the cue times are in) and Tracks first, the rest as they were.
        let rank = { (t: UInt32?) -> Int in t == info ? 0 : t == tracks ? 1 : 2 }
        let ordered = children.enumerated().sorted { (rank($0.element.target), $0.offset) < (rank($1.element.target), $1.offset) }.map(\.element)
        var body: [UInt8] = []
        for child in ordered {
            if child.element.id == 0xBF {
                // A CRC-32 is for the old order: a Void of the same size instead.
                body += [0xEC] + b[(child.element.start + 1)..<child.element.headerEnd] + [UInt8](repeating: 0, count: child.element.size)
            } else {
                body += b[child.element.start..<child.element.end]
            }
        }
        return Fix(range: seekHead.body..<seekHead.end, bytes: Data(body))
    }

    /// `chunk` (the file's bytes from `offset`) with the fix applied where they overlap.
    public static func apply(_ fix: Fix, to chunk: inout Data, at offset: Int) {
        let lo = max(fix.range.lowerBound, offset), hi = min(fix.range.upperBound, offset + chunk.count)
        guard lo < hi else { return }
        let start = chunk.startIndex
        chunk.replaceSubrange((start + lo - offset)..<(start + hi - offset),
                              with: fix.bytes[(fix.bytes.startIndex + lo - fix.range.lowerBound)..<(fix.bytes.startIndex + hi - fix.range.lowerBound)])
    }

    // MARK: EBML

    struct Element {
        var id: UInt32
        var start: Int
        var headerEnd: Int
        var size: Int
        var body: Int { headerEnd }
        var end: Int { headerEnd + size }
    }

    struct Reader {
        var bytes: [UInt8]

        /// A variable-length integer at `i`: its value (with or without the length marker) and width.
        func vint(at i: Int, keepMarker: Bool) -> (value: UInt64, width: Int)? {
            guard i < bytes.count else { return nil }
            let first = bytes[i]
            guard first != 0 else { return nil }
            let width = first.leadingZeroBitCount + 1
            guard i + width <= bytes.count else { return nil }
            var value = UInt64(keepMarker ? first : first & (0xFF >> width))
            for k in 1..<width { value = value << 8 | UInt64(bytes[i + k]) }
            return (value, width)
        }

        func element(at i: Int) -> Element? {
            guard let id = vint(at: i, keepMarker: true), id.width <= 4,
                  let size = vint(at: i + id.width, keepMarker: false), size.value < UInt64(Int.max / 2) else { return nil }
            let headerEnd = i + id.width + size.width
            return Element(id: UInt32(id.value), start: i, headerEnd: headerEnd, size: Int(size.value))
        }

        /// The element ID a Seek entry points at (its SeekID).
        func seekTarget(of seek: Element) -> UInt32? {
            var at = seek.body
            while at < seek.end, let el = element(at: at), el.end <= seek.end {
                if el.id == 0x53AB, el.size >= 1, el.size <= 4 {
                    return bytes[el.body..<el.end].reduce(0) { $0 << 8 | UInt32($1) }
                }
                at = el.end
            }
            return nil
        }
    }
}
