import AppCore
import Foundation
import Instrumentation
import JellyfinAPI

/// The queue, the same on every device signed in to the account: kept in
/// the user's Jellyfin display preferences (client "bumper"), so it needs no
/// server of ours. Pulled at launch, when the app comes back to the front and
/// every minute while it's open; pushed a moment after each change here. The
/// newer change wins.
@MainActor
final class QueueSync {
    static let planKey = "bumper.queue"
    static let stampKey = "bumper.queue.updated"

    private let store: QueueStore
    private let client: JellyfinClient
    private var pushTask: Task<Void, Never>?
    private var loop: Task<Void, Never>?

    init(store: QueueStore, client: JellyfinClient) {
        self.store = store
        self.client = client
    }

    func start() {
        store.onLocalChange = { [weak self] in self?.schedulePush() }
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pull()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        loop?.cancel()
        pushTask?.cancel()
        store.onLocalChange = nil
    }

    func pull() async {
        guard let prefs = try? await client.customPreferences(),
              let stamp = prefs[Self.stampKey].flatMap(Double.init) else { return }
        if stamp > store.updatedAt + 0.5, let json = prefs[Self.planKey], let data = json.data(using: .utf8),
           let plan = try? JSONDecoder().decode(QueuePlan.self, from: data) {
            store.applyRemote(plan, updatedAt: stamp)
        } else if store.updatedAt > stamp + 0.5 {
            schedulePush()                                    // ours is newer: the server should have it
        }
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            guard let data = try? JSONEncoder().encode(self.store.plan), let json = String(data: data, encoding: .utf8) else { return }
            do {
                try await self.client.setCustomPreferences([Self.planKey: json, Self.stampKey: String(self.store.updatedAt)])
                TraceFile.write("queue", "synced up (\(self.store.plan.entries.count) things)")
            } catch {
                TraceFile.write("queue", "sync failed: \(error)")
            }
        }
    }
}
