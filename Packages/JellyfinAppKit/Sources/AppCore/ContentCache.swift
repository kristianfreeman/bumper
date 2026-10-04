import Foundation
import Instrumentation

/// Stale-while-revalidate store for API responses.
///
/// Launch paints the home screen from the last snapshot *immediately* (no
/// spinner), then refreshes from the server and swaps in the diff. This is
/// most of the "feels instant" budget: a cold start on a LAN Jellyfin server is
/// still 150-400 ms of round trips; from cache it's one file read.
public actor ContentCache {
    public static let shared = ContentCache()

    private let directory: URL
    private var memory: [String: Data] = [:]

    public init(name: String = "content") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func value<T: Decodable & Sendable>(_ type: T.Type, for key: String) -> T? {
        let data = memory[key] ?? (try? Data(contentsOf: file(key)))
        guard let data else { return nil }
        memory[key] = data
        return try? Perf.measureSync("cache.decode", .apiDecode) { try JSONDecoder().decode(T.self, from: data) }
    }

    public func store<T: Encodable & Sendable>(_ value: T, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        memory[key] = data
        try? data.write(to: file(key), options: .atomic)
    }

    public func removeAll() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appending(path: String(safe) + ".json")
    }
}
