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

        public init(id: String, title: String, subtitle: String? = nil, imageURL: URL? = nil, progress: Double? = nil) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.imageURL = imageURL
            self.progress = progress
        }

        /// Select on the shelf: play (resuming). Bumper opens straight into the player.
        public var playURL: URL { URL(string: "\(TopShelfSnapshot.scheme)://play/\(id)")! }
        /// The page instead.
        public var displayURL: URL { URL(string: "\(TopShelfSnapshot.scheme)://item/\(id)")! }
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

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "TopShelf", directoryHint: .isDirectory)
            .appending(path: "snapshot.json")
    }

    public static func read() -> TopShelfSnapshot? {
        guard let url = Self.url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    /// True when it changed (the caller then tells the system to reload the shelf).
    @discardableResult
    public func write() -> Bool {
        guard let url = Self.url else { return false }
        var old = Self.read()
        old?.written = written
        guard old != self, let data = try? JSONEncoder().encode(self) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Links the app opens: `bumper://play/<id>` or `bumper://item/<id>`.
    public enum Link: Equatable, Sendable {
        case play(String), item(String)
        public init?(_ url: URL) {
            guard url.scheme == TopShelfSnapshot.scheme, let id = url.pathComponents.dropFirst().first, !id.isEmpty else { return nil }
            switch url.host() {
            case "play": self = .play(id)
            case "item": self = .item(id)
            default: return nil
            }
        }
    }
}
