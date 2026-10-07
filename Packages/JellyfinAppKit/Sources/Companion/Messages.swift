public import Foundation

/// The Apple TV ⇄ iPhone companion protocol: the TV tells the phone what it
/// shows (focus, playback, Queue); the phone asks the TV to do things.
/// JSON, one message per length-prefixed frame (`Frames`), over a TCP
/// connection found by Bonjour (`CompanionService.type`).
public enum CompanionService {
    public static let type = "_bumper._tcp"
    public static let version = 1
}

public struct CompanionItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// "1982 · 2 h 13 min", "Lost · S1 E3".
    public var subtitle: String?
    public var overview: String?
    /// Artwork straight from the Jellyfin server (16:9).
    public var imageURL: URL?
    public var minutes: Int?

    public init(id: String, title: String, subtitle: String? = nil, overview: String? = nil, imageURL: URL? = nil, minutes: Int? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
        self.imageURL = imageURL
        self.minutes = minutes
    }
}

public struct CompanionPlanEntry: Codable, Sendable, Hashable, Identifiable {
    public var item: CompanionItem
    public var start: Date
    public var suggested: Bool
    public var overruns: Bool
    public var id: String { item.id }

    public init(item: CompanionItem, start: Date, suggested: Bool, overruns: Bool) {
        self.item = item
        self.start = start
        self.suggested = suggested
        self.overruns = overruns
    }
}

/// A subtitle or audio track on the TV: its stream index and its name.
public struct CompanionTrack: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var detail: String?

    public init(id: Int, title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// A subtitle the TV's server found ("Find Subtitles"), best first.
public struct CompanionFoundSubtitle: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// "Best match · 92%", "46% match".
    public var detail: String

    public init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

/// Find Subtitles on the TV, as it goes.
public enum CompanionSubtitleSearch: Codable, Sendable, Hashable {
    case searching
    case results([CompanionFoundSubtitle])
    case failed(String)
}

/// The TV's sleep timer, as the phone sets it.
public enum CompanionSleep: Codable, Sendable, Hashable {
    case off
    case minutes(Int)
    case endOfItem
}

public struct CompanionNowPlaying: Codable, Sendable, Hashable {
    public var item: CompanionItem
    public var position: Double
    public var duration: Double
    public var paused: Bool
    // A video's controls (nil for an audiobook, or from an older TV):
    /// Clean 16:9 art, without a title in it.
    public var backdropURL: URL?
    public var subtitles: [CompanionTrack]?
    /// The subtitle on (a stream index); nil when off.
    public var subtitle: Int?
    public var audio: [CompanionTrack]?
    public var audioTrack: Int?
    public var untracked: Bool?
    public var sleep: CompanionSleep?
    /// "18m", "End of episode".
    public var sleepLabel: String?
    /// "episode", "film": for "End of This Episode".
    public var kind: String?
    /// What plays after it, then the rest of the Queue.
    public var upNext: [CompanionItem]?
    /// Find Subtitles, while it's searching or has results.
    public var subtitleSearch: CompanionSubtitleSearch?

    public init(item: CompanionItem, position: Double, duration: Double, paused: Bool) {
        self.item = item
        self.position = position
        self.duration = duration
        self.paused = paused
    }
}

/// Everything the phone shows about the TV.
public struct CompanionState: Codable, Sendable, Hashable {
    public var tvName: String
    public var userName: String?
    /// What's under focus on the TV right now.
    public var focused: CompanionItem?
    public var playing: CompanionNowPlaying?
    public var queue: [CompanionPlanEntry]
    public var doneBy: Date?
    /// "Three things — done around 11:40 PM."
    public var queueSummary: String

    public init(tvName: String, userName: String? = nil, focused: CompanionItem? = nil, playing: CompanionNowPlaying? = nil,
                queue: [CompanionPlanEntry] = [], doneBy: Date? = nil, queueSummary: String = "") {
        self.tvName = tvName
        self.userName = userName
        self.focused = focused
        self.playing = playing
        self.queue = queue
        self.doneBy = doneBy
        self.queueSummary = queueSummary
    }
}

/// What the phone asks for.
public enum CompanionCommand: Codable, Sendable, Hashable {
    case play(itemId: String)
    /// Play from the start (`resume` false), or Untracked (on a loop,
    /// nothing marked watched; a show from a random episode).
    case playItem(itemId: String, resume: Bool, background: Bool)
    case addToQueue(itemId: String)
    case removeFromQueue(itemId: String)
    case moveInQueue(itemId: String, by: Int)
    case setDoneBy(Date?)
    case playPause
    /// To this many seconds in.
    case seek(to: Double)
    /// Back (negative) or ahead by this many seconds.
    case skip(by: Double)
    /// A subtitle by stream index; nil turns them off.
    case selectSubtitle(Int?)
    case selectAudio(Int)
    case setUntracked(Bool)
    case setSleep(CompanionSleep)
    /// Find Subtitles: the TV's server searches; results come in the state.
    case findSubtitles
    case useFoundSubtitle(id: String)
    case cancelSubtitleSearch
    /// Titles matching words (the TV searches its library).
    case search(String)
    /// A request in plain words ("something funny from the 80s") — the
    /// phone may have rewritten it with its on-device model first.
    case ask(String)
}

public enum CompanionMessage: Codable, Sendable, Hashable {
    case hello(name: String, version: Int)
    case state(CompanionState)
    case results(query: String, items: [CompanionItem], understood: String?)
    case command(CompanionCommand)
}

/// Length-prefixed frames: 4-byte big-endian length, then that many bytes
/// of JSON.
public enum Frames {
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()

    public static func encode(_ message: CompanionMessage) throws -> Data {
        let body = try encoder.encode(message)
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    /// Collects bytes as they arrive; hands back whole messages.
    public struct Reader: Sendable {
        private var buffer = Data()
        public init() {}

        public mutating func append(_ data: Data) throws -> [CompanionMessage] {
            buffer.append(data)
            var out: [CompanionMessage] = []
            while buffer.count >= 4 {
                let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                guard length < 8 << 20 else { buffer.removeAll(); throw CocoaError(.coderReadCorrupt) }
                guard buffer.count >= 4 + length else { break }
                let body = buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + length)
                buffer.removeFirst(4 + length)
                out.append(try decoder.decode(CompanionMessage.self, from: body))
            }
            return out
        }
    }
}
