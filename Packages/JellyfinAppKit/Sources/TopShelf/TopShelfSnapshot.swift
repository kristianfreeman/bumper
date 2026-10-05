public import Foundation

/// What the Top Shelf shows above Bumper's icon on the Apple TV Home Screen:
/// written by the app whenever Home loads, read by the Top Shelf extension
/// (which can't talk to the server itself). Shared through the app group.
public struct TopShelfSnapshot: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var subtitle: String?
        public var imageURL: URL?
        /// 0…1, for the progress bar on in-progress things.
        public var progress: Double?
        /// A link instead of something to play (a library).
        public var link: URL?
        /// Tall posters for things, wide pictures for libraries.
        public var shape: Shape?
        public enum Shape: String, Codable, Sendable { case poster, wide }

        public init(id: String, title: String, subtitle: String? = nil, imageURL: URL? = nil, progress: Double? = nil, link: URL? = nil, shape: Shape? = nil) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.imageURL = imageURL
            self.progress = progress
            self.link = link
            self.shape = shape
        }

        /// Select on the shelf: play (resuming), or follow the link.
        public var playURL: URL { link ?? URL(string: "\(TopShelfSnapshot.scheme)://play/\(id)")! }
        /// The page instead.
        public var displayURL: URL { link ?? URL(string: "\(TopShelfSnapshot.scheme)://item/\(id)")! }
    }

    public struct Section: Codable, Sendable, Equatable {
        public var title: String
        public var items: [Item]
        public init(title: String, items: [Item]) {
            self.title = title
            self.items = items
        }
    }

    public var sections: [Section]
    public var written: Date

    public init(sections: [Section], written: Date = .now) {
        self.sections = sections
        self.written = written
    }

    public static let appGroup = "group.com.kristianfreeman.bumper"
    public static let scheme = "bumper"

    /// Where the shelf's files live (the snapshot, and its tile artwork).
    public static var directory: URL? { url?.deletingLastPathComponent() }

    static var url: URL? {
        // tvOS lets apps write only under Library/Caches, in a shared
        // container too (the top level is read-only: "Operation not permitted").
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Library/Caches/TopShelf", directoryHint: .isDirectory)
            .appending(path: "snapshot.json")
    }

    public static func read() -> TopShelfSnapshot? {
        guard let url = Self.url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    public enum WriteResult: Equatable, Sendable { case written, unchanged, noContainer, failed(String) }

    /// `.written` when it changed (the caller then tells the system to reload the shelf).
    @discardableResult
    public func write() -> WriteResult {
        guard let url = Self.url else { return .noContainer }
        var old = Self.read()
        old?.written = written
        guard old != self else { return .unchanged }
        do {
            let data = try JSONEncoder().encode(self)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return .written
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Links the app opens: `bumper://play/<id>`, `bumper://item/<id>`,
    /// `bumper://library/<id>`, `bumper://queue`, `bumper://search`.
    public enum Link: Equatable, Sendable {
        case play(String), item(String), library(String), queue, search

        public init?(_ url: URL) {
            guard url.scheme == TopShelfSnapshot.scheme else { return nil }
            let id = url.pathComponents.dropFirst().first.flatMap { $0.isEmpty ? nil : $0 }
            switch (url.host(), id) {
            case ("play", let id?): self = .play(id)
            case ("item", let id?): self = .item(id)
            case ("library", let id?): self = .library(id)
            case ("queue", _), ("tonight", _): self = .queue         // "tonight": the name before
            case ("search", _): self = .search
            default: return nil
            }
        }

        public var url: URL {
            let s = TopShelfSnapshot.scheme
            switch self {
            case .play(let id): return URL(string: "\(s)://play/\(id)")!
            case .item(let id): return URL(string: "\(s)://item/\(id)")!
            case .library(let id): return URL(string: "\(s)://library/\(id)")!
            case .queue: return URL(string: "\(s)://queue")!
            case .search: return URL(string: "\(s)://search")!
            }
        }
    }
}
