import Companion
import Foundation
import Network
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The phone's side: finds Apple TVs running the app, connects to one, and
/// mirrors what it shows.
@MainActor
@Observable
final class CompanionModel {
    struct TV: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    private(set) var tvs: [TV] = []
    private(set) var connectedTo: String?
    private(set) var state: CompanionState?
    private(set) var results: [CompanionItem] = []
    private(set) var resultsTitle: String?
    private(set) var searching = false

    private let queue = DispatchQueue(label: "companion.phone")
    private var browser: NWBrowser?
    private var connection: CompanionConnection?

    func startBrowsing() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: CompanionService.type, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { r -> TV? in
                if case .service(let name, _, _, _) = r.endpoint { return TV(name: name, endpoint: r.endpoint) }
                return nil
            }
            Task { @MainActor in
                guard let self else { return }
                self.tvs = found.sorted { $0.name < $1.name }
                // One TV: connect without asking.
                if self.connection == nil, let only = self.tvs.first, self.tvs.count == 1 { self.connect(only) }
            }
        }
        b.start(queue: queue)
        browser = b
    }

    func connect(_ tv: TV) {
        connection?.cancel()
        let c = CompanionConnection(to: tv.endpoint, queue: queue)
        c.onMessage = { [weak self] message in Task { @MainActor in self?.receive(message) } }
        c.onClose = { [weak self] in
            Task { @MainActor in
                guard let self, self.connection === c else { return }
                self.connection = nil
                self.connectedTo = nil
                self.state = nil
                // Try again shortly (the TV may have gone to sleep, or restarted the app).
                try? await Task.sleep(for: .seconds(2))
                if let again = self.tvs.first(where: { $0.name == tv.name }) { self.connect(again) }
            }
        }
        connection = c
        connectedTo = tv.name
        c.start()
    }

    func send(_ command: CompanionCommand) { connection?.send(.command(command)) }

    func search(_ words: String) {
        let trimmed = words.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { results = []; resultsTitle = nil; return }
        searching = true
        send(.search(trimmed))
    }

    /// A request in plain words. Where Apple Intelligence is available the
    /// phone's on-device model first turns it into the words the TV's
    /// filter understands; elsewhere the TV reads it as it is.
    func ask(_ words: String) async {
        let trimmed = words.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searching = true
        send(.ask(await Self.rewrite(trimmed)))
    }

    static var hasOnDeviceModel: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static func rewrite(_ words: String) async -> String {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return words }
        let session = LanguageModelSession(instructions: """
            You turn a viewer's request for something to watch into short filter words, \
            using only: a genre (comedy, horror, action, romance, drama, mystery, thriller, science fiction, \
            animation, documentary, family, western), a decade like "1980s", "unwatched", "under N minutes", \
            "highly rated", "this week". Reply with just the words, separated by spaces.
            """)
        if let reply = try? await session.respond(to: words) {
            return reply.content + " " + words          // the TV reads both: the model's words win where they're clearer
        }
        #endif
        return words
    }

    private func receive(_ message: CompanionMessage) {
        switch message {
        case .hello(let name, _): connectedTo = name
        case .state(let s): state = s
        case .results(let query, let items, let understood):
            results = items
            resultsTitle = understood.map { "“\(query)” — \($0)" } ?? "“\(query)”"
            searching = false
        case .command: break
        }
    }
}
