public import Foundation
public import JellyfinAPI
import Instrumentation
import Synchronization

/// Watch progress the server didn't get (offline: a download on a plane),
/// kept until it can be delivered — so what you watched offline still
/// resumes in the right place, and counts as watched, everywhere.
public final class PlaystateOutbox: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var itemId: String
        public var positionTicks: Int64
        public var played: Bool
        public var at: Date
    }

    /// UserDefaults is thread-safe; the lock keeps read-modify-write whole.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String
    private let lock = Mutex(())

    public init(defaults: UserDefaults = .standard, account: String) {
        self.defaults = defaults
        key = "playstate.outbox.\(account)"
    }

    public var entries: [Entry] {
        lock.withLock { _ in (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? [] }
    }

    /// The latest for an item replaces what was there.
    public func keep(itemId: String, positionTicks: Int64, played: Bool) {
        lock.withLock { _ in
            var list = (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
            list.removeAll { $0.itemId == itemId }
            list.append(Entry(itemId: itemId, positionTicks: positionTicks, played: played, at: .now))
            defaults.set(try? JSONEncoder().encode(list), forKey: key)
        }
    }

    private func drop(_ itemId: String, at: Date) {
        lock.withLock { _ in
            var list = (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
            list.removeAll { $0.itemId == itemId && $0.at <= at }
            defaults.set(try? JSONEncoder().encode(list), forKey: key)
        }
    }

    /// Sends what's waiting; what still can't go stays.
    public func deliver(with client: JellyfinClient) async {
        for entry in entries {
            do {
                if entry.played { try await client.setPlayed(true, itemId: entry.itemId) }
                else { try await client.updatePlaybackPosition(itemId: entry.itemId, ticks: entry.positionTicks, lastPlayed: entry.at) }
                drop(entry.itemId, at: entry.at)
                TraceFile.write("playstate", "delivered \(entry.itemId) (\(entry.played ? "watched" : "\(entry.positionTicks / 10_000_000) s"))")
            } catch {
                return                                            // still offline: try again later
            }
        }
    }
}
